{ denTest, ... }:
{
  flake.tests.fx-edges-pi = {

    # aware/dedup defaults: dedupMode defaults, allScopeIds is OMITTED (so the
    # materializer's derive-from-perScope default applies — the per-host site).
    test-static-pi-aware-defaults = denTest (
      { den, ... }:
      let
        pi = den.lib.aspects.fx.edges.pi.mkStaticPi {
          rootScopeId = "host=igloo";
          scopeContexts = {
            "host=igloo" = { };
          };
          scopeParent = { };
          scopeIsolated = { };
          isolationMode = "aware";
        };
      in
      {
        expr = {
          inherit (pi)
            rootScopeId
            isolationMode
            dedupMode
            contextsAreAugmented
            classInject
            ;
          hasAllScopeIds = pi ? allScopeIds;
        };
        expected = {
          rootScopeId = "host=igloo";
          isolationMode = "aware";
          dedupMode = "dedup";
          contextsAreAugmented = true;
          classInject = null;
          hasAllScopeIds = false;
        };
      }
    );

    # blind/raw spawn dials: explicit dedupMode + allScopeIds carried through.
    test-static-pi-blind-raw = denTest (
      { den, ... }:
      let
        pi = den.lib.aspects.fx.edges.pi.mkStaticPi {
          rootScopeId = "spawn";
          scopeContexts = { };
          scopeParent = { };
          scopeIsolated = { };
          isolationMode = "blind";
          dedupMode = "raw";
          allScopeIds = [
            "spawn"
            "a"
          ];
        };
      in
      {
        expr = {
          inherit (pi) isolationMode dedupMode allScopeIds;
        };
        expected = {
          isolationMode = "blind";
          dedupMode = "raw";
          allScopeIds = [
            "spawn"
            "a"
          ];
        };
      }
    );

  };
}
