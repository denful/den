# `__providesForwarded` marks the names a merge forwarded from `provides` onto
# an aspect's own top level, so `classifyKeys` skips them instead of reading
# them as the aspect's own class or nested content. All three construction
# sites in nix/lib/aspects/types.nix compute that marker with the same shadow
# test — `!(own ? k)` — which cannot tell a name the AUTHOR wrote at top level
# from a name a PREVIOUS merge forwarded there. So re-merging an already-merged
# aspect (an alias, a nested-key alias, an `<angle/bracket>` include) read its
# own earlier forward as a direct definition, cleared the marker, and let the
# child be classified. Where the child's name is a registered class, the child
# aspect itself was emitted as that class's content (#683: a `provides.packages`
# child surfaced as `flake.packages.<system>`, fields and all).
{ denTest, inputs, ... }:
{
  flake.tests.deadbugs.issue-683-remerge-provides-forwarded = {

    # `src` is the live control: it is merged once and classifies correctly.
    # The two aliases are the same value merged a second time, at the two
    # sites a re-merge is directly readable from.
    test-marker-survives-a-remerge = denTest (
      { den, ... }:
      let
        cls = den.lib.aspects.fx.keyClassification.classifyKeys null;
        classified = a: (cls a).classKeys;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.d683src.provides.child.provides.nixos.nixos.environment.etc."d683".text = "y";
        # site A — mergeWithAspectMeta: an already-merged aspect aliased to a root slot.
        den.aspects.d683a = den.aspects.d683src.provides.child;
        # site C — aspectContentType: the same value at a nested freeform key.
        den.aspects.d683c.holder = den.aspects.d683src.provides.child;

        expr = {
          srcMarker = den.aspects.d683src.provides.child.__providesForwarded or "MISSING";
          aMarker = den.aspects.d683a.__providesForwarded or "MISSING";
          cMarker = den.aspects.d683c.holder.__providesForwarded or "MISSING";
          srcClassified = classified den.aspects.d683src.provides.child;
          aClassified = classified den.aspects.d683a;
          cClassified = classified den.aspects.d683c.holder;
        };
        expected = {
          srcMarker = [ "nixos" ];
          aMarker = [ "nixos" ];
          cMarker = [ "nixos" ];
          srcClassified = [ ];
          aClassified = [ ];
          cClassified = [ ];
        };
      }
    );

    # Site B — mergeFunctions' functor-carrying attrset branch, reached by
    # including an already-merged aspect. End-to-end rather than by marker,
    # because the reported symptom is the child aspect's own fields arriving
    # as flake output content.
    test-provides-packages-does-not-reach-flake-packages = denTest (
      {
        config,
        den,
        __findFile,
        ...
      }:
      {
        imports = [ inputs.den.flakeOutputs.packages ];
        _module.args.__findFile = den.lib.__findFile;

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ <d683group/tools> ];
        den.aspects.d683group.provides.tools = {
          includes = [ <d683group/tools/packages> ];
          provides.packages = {
            homeManager =
              { pkgs, ... }:
              {
                home.packages = [ ];
              };
          };
        };

        expr = builtins.attrNames (config.flake.packages.x86_64-linux or { });
        expected = [ ];
      }
    );
  };
}
