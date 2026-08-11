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

    # CONTROL: a navigated child carries __provider but no __contentValues, and
    # nothing may invent an empty one for it — an empty __contentValues
    # re-flattens to no definitions at all, turning a loud failure into an empty
    # result. Green on both sides of the fix; it pins the invariant rather than
    # reproducing a specific break.
    test-navigated-child-keeps-no-content-values = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.mid._.net.nixos.boot.kernelParams = [ "net-param" ];

        den.aspects.igloo.includes = [ den.aspects.mid._.net ];

        expr = {
          invented = den.aspects.mid._.net ? __contentValues;
          applied = builtins.filter (p: p == "net-param") igloo.boot.kernelParams;
        };
        expected = {
          invented = false;
          applied = [ "net-param" ];
        };
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
