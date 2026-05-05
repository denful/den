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
        newScopeId = mkScopeId scopedCtx;
        isSameScope = newScopeId == parentScope;
        scopeHandlers = constantHandler (
          scopedCtx // lib.optionalAttrs (entityClass != null) { class = entityClass; }
        );
        allDeferred = (state.scopedDeferredIncludes or (_: { })) null;
        parentItems = allDeferred.${parentScope} or [ ];
        parentPolicies =
          let
            all = state.scopedAspectPolicies null;
          in
          all.${parentScope} or { };
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
            scopeContexts = _: (state.scopeContexts null) // { ${newScopeId} = scopedCtx; };
            scopeParent =
              _: (state.scopeParent null) // lib.optionalAttrs (!isSameScope) { ${newScopeId} = parentScope; };
            scopedAspectPolicies =
              _:
              let
                all = state.scopedAspectPolicies null;
              in
              all // { ${newScopeId} = (all.${newScopeId} or { }) // parentPolicies; };
            # Record source policy name — installPolicies reads this to
            # exclude the source policy from dispatch at this scope.
            # Invariant: policies don't apply to their own outputs.
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
