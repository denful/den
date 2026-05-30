# Effect handler: widen-context
# Updates scopeContexts with enriched context after policy enrichment stabilizes.
# Extracted from policy/iterate.nix widenAndContinue.
_: {
  widenContextHandler = {
    "widen-context" =
      { param, state }:
      let
        enrichedCtx = param.currentCtx // param.enrichment;
      in
      let
        updated = (state.scopeContexts null) // {
          ${state.currentScope} = enrichedCtx;
        };
      in
      {
        resume = null;
        state = state // {
          scopeContexts = _: updated;
        };
      };
  };
}
