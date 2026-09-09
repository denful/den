# A nested aspect key carries its identity on the content wrapper, via
# __aspectChain. Anything that takes definitions out of the wrapper has to keep
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

    # An annotated child three levels down carries __aspectChain and no
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
    #
    # Also asserts identity, not only delivery: den.aspects.base already
    # carries a meaningful name+chain of its own, so wrapperToAspect must not
    # overwrite it with the alias's nested position ("libraries/alias") — an
    # author's name outranks its position. ctrlbase is a live control: an
    # ordinary directly-included aspect, unaffected by the alias, present in
    # both arms.
    test-alias-merged-aspect = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        hostEntity = den.hosts.x86_64-linux.igloo;
        ids = map (a: a.identity) hostEntity.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.base.nixos.boot.kernelParams = [ "s-base" ];
        den.aspects.libraries.alias = den.aspects.base;
        den.aspects.ctrlbase.nixos.boot.kernelParams = [ "s-ctrl" ];

        den.aspects.igloo.includes = [
          den.aspects.libraries.alias
          den.aspects.ctrlbase
        ];

        expr = {
          params = builtins.sort (a: b: a < b) (builtins.filter (lib.hasPrefix "s-") igloo.boot.kernelParams);
          hasAlias = hostEntity.hasAspect den.aspects.libraries.alias;
          hasBase = hostEntity.hasAspect den.aspects.base;
          hasCtrl = hostEntity.hasAspect den.aspects.ctrlbase;
          hasBaseId = builtins.elem "base" ids;
          hasCtrlId = builtins.elem "ctrlbase" ids;
        };
        expected = {
          params = [
            "s-base"
            "s-ctrl"
          ];
          hasAlias = true;
          hasBase = true;
          hasCtrl = true;
          hasBaseId = true;
          hasCtrlId = true;
        };
      }
    );

    # O2 — an authored `name` at a nested key survives wrapperToAspect: an
    # author's name outranks its position. Two attribution sites, per the
    # attribution trap: holder.slot is depth-1, stamped by
    # aspectContentType.merge's `provider` field; deep.mid.slot is depth-2,
    # stamped by annotateChildren. toplevel is the live control — a
    # top-level authored name already won before this fix (it never reaches
    # wrapperToAspect), so its presence in both arms proves the readout
    # itself is not empty.
    test-authored-name-at-nested-key-outranks-position = denTest (
      { den, ... }:
      let
        ids = map (a: a.identity) den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.holder.slot = {
          name = "author-chose-this";
          nixos.boot.kernelParams = [ "s-holder" ];
        };
        den.aspects.deep.mid.slot = {
          name = "author-chose-deep";
          nixos.boot.kernelParams = [ "s-deep" ];
        };
        den.aspects.toplevel = {
          name = "author-chose-that";
          nixos.boot.kernelParams = [ "s-top" ];
        };

        den.aspects.igloo.includes = [
          den.aspects.holder.slot
          den.aspects.deep.mid.slot
          den.aspects.toplevel
        ];

        expr = {
          hasHolderName = builtins.elem "holder/author-chose-this" ids;
          hasDeepName = builtins.elem "deep/mid/author-chose-deep" ids;
          hasTopName = builtins.elem "author-chose-that" ids;
          noPositionalIds = !(builtins.elem "holder/slot" ids) && !(builtins.elem "deep/mid/slot" ids);
        };
        expected = {
          hasHolderName = true;
          hasDeepName = true;
          hasTopName = true;
          noPositionalIds = true;
        };
      }
    );

    # O3 — the loud path: den's own sentinel ("<anon>") is not an authored
    # name and stays overridable by position, per the ruling's scope ("an
    # author's name"). This is the cell that discriminates the shipped guard
    # (component-wise, gated on isMeaningfulName) from the nearest wrong one
    # (component-wise, gated on `? name` alone) — the wrong guard treats
    # "<anon>" as authored and regresses this identity to a positional/index
    # one instead of leaving it alone.
    test-sentinel-name-at-nested-key-stays-overridden = denTest (
      { den, ... }:
      let
        ids = map (a: a.identity) den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.holder.anonslot = {
          name = "<anon>";
          nixos.boot.kernelParams = [ "s-anon" ];
        };

        den.aspects.igloo.includes = [ den.aspects.holder.anonslot ];

        expr = builtins.elem "holder/anonslot" ids;
        expected = true;
      }
    );

    # O4 — regression fence, not a discriminator (no candidate mechanism
    # measured gives this a red arm). compile-static's chain registry only
    # fires where meta.aspect-chain is null (fillsChain); this mechanism
    # always leaves it non-null, so raw-value equality is untouched: two
    # independently-owned inline "tools" literals keep two identities, and
    # one shared "shared-tools" literal referenced by two owners keeps one
    # (walk-order-dependent, claimed by whichever owner is included first).
    test-name-guard-preserves-raw-value-equality = denTest (
      { den, igloo, ... }:
      let
        sharedTools = {
          name = "shared-tools";
          nixos.environment.etc."shared-tools".text = "yes";
        };
        toolsNodes = builtins.filter (n: n.name == "tools") den.hosts.x86_64-linux.igloo.aspects;
        sharedNodes = builtins.filter (n: n.name == "shared-tools") den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.alpha
          den.aspects.beta
        ];

        den.aspects.alpha.includes = [
          {
            name = "tools";
            nixos.environment.etc."alpha-tools".text = "yes";
          }
          sharedTools
        ];
        den.aspects.beta.includes = [
          {
            name = "tools";
            nixos.environment.etc."beta-tools".text = "yes";
          }
          sharedTools
        ];

        expr = {
          toolsIds = builtins.sort builtins.lessThan (map (n: n.identity) toolsNodes);
          sharedIds = builtins.sort builtins.lessThan (map (n: n.identity) sharedNodes);
          alpha = igloo.environment.etc ? "alpha-tools";
          beta = igloo.environment.etc ? "beta-tools";
        };
        expected = {
          toolsIds = [
            "alpha/tools"
            "beta/tools"
          ];
          sharedIds = [ "alpha/shared-tools" ];
          alpha = true;
          beta = true;
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
