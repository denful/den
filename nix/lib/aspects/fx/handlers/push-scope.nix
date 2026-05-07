# Effect handler: push-scope
# Atomically sets currentScope, scopeContexts, scopeParent,
# inherits scopedAspectPolicies, and fans out scopedDeferredIncludes.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx.handlers) constantHandler;
  inherit (den.lib.aspects.fx.pipeline) mkScopeId;

  pushScopeHandler = {
    "push-scope" =
      { param, state }:
      let
        inherit (param) scopedCtx entityClass parentScope;
        sourcePolicyName = param.sourcePolicyName or null;
        entityKind = param.entityKind or null;
        newScopeId = mkScopeId scopedCtx;
        isSameScope = newScopeId == parentScope;
        scopeHandlers = constantHandler (
          scopedCtx // lib.optionalAttrs (entityClass != null) { class = entityClass; }
        );
        allDeferred = (state.scopedDeferredIncludes or (_: { })) null;
        parentItems = allDeferred.${parentScope} or [ ];
      in
      {
        resume = {
          inherit scopeHandlers;
          scopeId = newScopeId;
        };
        state =
          state
          // {
            currentScope = newScopeId;
            # Save and reset inLateDispatch — each scope level gets its own
            # late-dispatch opportunity.  restore-scope pops the saved value.
            inLateDispatch = false;
            inLateDispatchStack = (state.inLateDispatchStack or [ ]) ++ [ (state.inLateDispatch or false) ];
            scopeContexts =
              _:
              (state.scopeContexts null)
              // {
                ${newScopeId} = scopedCtx;
              };
            scopeParent =
              _: (state.scopeParent null) // lib.optionalAttrs (!isSameScope) { ${newScopeId} = parentScope; };
            # No parent inheritance — policies fire where registered, not at
            # child scopes.  Cascade is through effects, not re-dispatch.
            scopedAspectPolicies =
              _:
              let
                all = state.scopedAspectPolicies null;
              in
              all // { ${newScopeId} = all.${newScopeId} or { }; };
            # Record source policy name — installPolicies reads this to
            # exclude the source policy from dispatch at this scope.
            # Invariant: policies don't apply to their own outputs.
            # Track entity class per scope — separate from scopeContexts to avoid
            # affecting provides/enrichment.  Read by bind's state fallback and
            # subtree extraction.
            scopeEntityClass =
              _:
              ((state.scopeEntityClass or (_: { })) null)
              // lib.optionalAttrs (entityClass != null) {
                ${newScopeId} = entityClass;
              };
            # Track which entity kind each scope was created for.
            # Used by collectFromPeers to filter by the scope's own entity kind
            # rather than all entity kinds inherited from parent context.
            scopeEntityKind =
              _:
              ((state.scopeEntityKind or (_: { })) null)
              // lib.optionalAttrs (entityKind != null) {
                ${newScopeId} = entityKind;
              };
            scopeSourcePolicy =
              _:
              ((state.scopeSourcePolicy or (_: { })) null)
              // lib.optionalAttrs (sourcePolicyName != null) {
                ${newScopeId} = sourcePolicyName;
              };
          }
          // lib.optionalAttrs (parentItems != [ ]) {
            scopedDeferredIncludes =
              _:
              allDeferred
              // {
                ${newScopeId} = (allDeferred.${newScopeId} or [ ]) ++ parentItems;
              };
          };
      };
  };
in
{
  inherit pushScopeHandler;
}
