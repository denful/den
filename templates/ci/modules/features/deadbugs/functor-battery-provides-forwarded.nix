# `mkUnderscore`'s three construction sites (nix/lib/aspects/types.nix) all
# compute `unshadowedProvides` and publish it as `__providesForwarded`, so
# `classifyKeys` (key-classification.nix) knows to skip a forwarded provides
# child during classification — the same child is already reachable via
# `.provides`/`._` and must not ALSO be classified as the aspect's own
# content. Site B (`mergeFunctions`'s attrset-with-`__functor` branch, the
# shape a functor-carrying battery like import-tree/forward takes) never
# computed or emitted the marker: `__providesForwarded` read back "MISSING"
# there while sites A (`mergeWithAspectMeta`) and C (`aspectContentType`)
# both emit it correctly, so a battery's forwarded provides child was
# classified (and thus dispatched) at B only.
{ denTest, ... }:
{
  flake.tests.deadbugs.functor-battery-provides-forwarded = {

    # Three-way comparison, one provides-child name (`d9leak`), one per
    # construction site. B is the site under test; A and C are live
    # controls proving the marker/classification predicate discriminates.
    test-marker-and-classification-agree-at-all-sites = denTest (
      { den, ... }:
      let
        cls = den.lib.aspects.fx.keyClassification.classifyKeys null;
        allKeys = c: c.classKeys ++ c.nestedKeys ++ c.unregisteredClassKeys ++ c.pipeKeys;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # site A — declared submodule, direct `provides.d9leak`.
        den.aspects.d9fa.provides.d9leak.nixos.environment.etc."d9-fa".text = "y";
        # site B — functor-carrying battery attrset, `_.d9leak` write.
        den.aspects.d9fh.provides.d9fb = {
          __functor = _self: _args: { };
          _.d9leak.nixos.environment.etc."d9-fb".text = "y";
        };
        # site C — nested freeform key, direct `provides.d9leak`.
        den.aspects.d9fc.holder.provides.d9leak.nixos.environment.etc."d9-fc".text = "y";

        expr = {
          aMarker = den.aspects.d9fa.__providesForwarded or "MISSING";
          bMarker = den.aspects.d9fh.d9fb.__providesForwarded or "MISSING";
          cMarker = den.aspects.d9fc.holder.__providesForwarded or "MISSING";
          aClassified = builtins.elem "d9leak" (allKeys (cls den.aspects.d9fa));
          bClassified = builtins.elem "d9leak" (allKeys (cls den.aspects.d9fh.d9fb));
          cClassified = builtins.elem "d9leak" (allKeys (cls den.aspects.d9fc.holder));
        };
        expected = {
          aMarker = [ "d9leak" ];
          bMarker = [ "d9leak" ];
          cMarker = [ "d9leak" ];
          aClassified = false;
          bClassified = false;
          cClassified = false;
        };
      }
    );
  };
}
