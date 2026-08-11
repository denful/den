# A nested aspect key carries its identity on the content wrapper, via
# __provider. Anything that takes definitions out of the wrapper has to keep
# that identity, or the definitions resolve to an anonymous per-inclusion name,
# gate dedup stops matching them, and their content lands once per include path.
{ denTest, ... }:
{
  flake.tests.deadbugs.nested-key-wrapper-identity = {

    # All definitions parametric — the wrapper is the only identity carrier.
    test-all-parametric-nested-key-dedups = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.libraries.alpha =
          { host, ... }:
          {
            nixos.boot.kernelParams = [ "from-${host.hostName}" ];
          };

        den.aspects.parent1.includes = [ den.aspects.libraries.alpha ];
        den.aspects.parent2.includes = [ den.aspects.libraries.alpha ];

        den.aspects.igloo.includes = [
          den.aspects.parent1
          den.aspects.parent2
        ];

        expr = builtins.filter (lib.hasPrefix "from-") igloo.boot.kernelParams;
        expected = [ "from-igloo" ];
      }
    );

    # Two parametric definitions of one nested key, reached by two paths.
    test-multi-parametric-nested-key-dedups = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.libraries.alpha =
              { host, ... }:
              {
                nixos.boot.kernelParams = [ "a-${host.hostName}" ];
              };
          }
          {
            den.aspects.libraries.alpha =
              { user, ... }:
              {
                nixos.boot.kernelParams = [ "b-${user.userName}" ];
              };
          }
        ];

        den.aspects.parent1.includes = [ den.aspects.libraries.alpha ];
        den.aspects.parent2.includes = [ den.aspects.libraries.alpha ];

        den.aspects.igloo.includes = [
          den.aspects.parent1
          den.aspects.parent2
        ];

        expr = builtins.sort (a: b: a < b) (
          builtins.filter (p: lib.hasPrefix "a-" p || lib.hasPrefix "b-" p) igloo.boot.kernelParams
        );
        expected = [
          "a-igloo"
          "b-tux"
        ];
      }
    );

    # An annotated child three levels down carries __provider and no
    # __contentValues of its own. Nothing may invent an empty one when it passes
    # through providerType: rawHasCV pins that the child starts without one, so
    # the test cannot pass by accident on a shallower shape whose middle name IS
    # the nested key and therefore has one already.
    test-annotated-child-gains-no-content-values = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.libraries.services.network.cilium.nixos.boot.kernelParams = [ "s-cil" ];
        den.aspects.mid._.net = den.aspects.libraries.services.network;

        expr = {
          rawHasCV = den.aspects.libraries.services.network ? __contentValues;
          hopHasCV = den.aspects.mid._.net ? __contentValues;
        };
        expected = {
          rawHasCV = false;
          hopHasCV = false;
        };
      }
    );

    # A mixed wrapper re-exported through a providerType hop and then assigned to
    # a nested key. The flatten must not expand an already-converted aspect back
    # into its definitions — doing so discards the includes the parametric half
    # was moved into, keeping only the static side.
    test-mixed-wrapper-reexport = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.libraries.alpha =
              { host, ... }:
              {
                nixos.boot.kernelParams = [ "a=${host.hostName}" ];
              };
          }
          {
            den.aspects.libraries.alpha.nixos.boot.kernelParams = [ "s" ];
          }
        ];

        den.aspects.mid._.thing = den.aspects.libraries.alpha;
        den.aspects.consumer.child = den.aspects.mid._.thing;

        den.aspects.igloo.includes = [ den.aspects.consumer.child ];

        expr = builtins.sort (a: b: a < b) (
          builtins.filter (p: lib.hasPrefix "a=" p || p == "s") igloo.boot.kernelParams
        );
        expected = [
          "a=igloo"
          "s"
        ];
      }
    );

    # Aliasing a merged aspect: every merged aspect carries __functor, so a
    # functor-blind functionArgs throws on the alias.
    test-alias-merged-aspect = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.base.nixos.boot.kernelParams = [ "s-base" ];
        den.aspects.libraries.alias = den.aspects.base;

        den.aspects.igloo.includes = [ den.aspects.libraries.alias ];

        expr = builtins.filter (lib.hasPrefix "s-") igloo.boot.kernelParams;
        expected = [ "s-base" ];
      }
    );

    # CONTROL: a providerType hop (_ slot) included from a nested key — both
    # halves survive the hop. Green before and after.
    test-underscore-hop-then-nested-key = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.source._.slot =
          { host, ... }:
          {
            nixos.boot.kernelParams = [ "param-${host.hostName}" ];
          };

        den.aspects.middle.hop.includes = [ den.aspects.source._.slot ];
        den.aspects.middle.hop.nixos.boot.kernelParams = [ "static" ];

        den.aspects.igloo.includes = [ den.aspects.middle.hop ];

        expr = builtins.sort (a: b: a < b) (
          builtins.filter (p: lib.hasPrefix "param-" p || p == "static") igloo.boot.kernelParams
        );
        expected = [
          "param-igloo"
          "static"
        ];
      }
    );

  };
}
