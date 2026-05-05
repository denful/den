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
            scopeContexts = _: (state.scopeContexts null) // { ${newScopeId} = scopedCtx; };
            scopeParent =
              _: (state.scopeParent null) // lib.optionalAttrs (!isSameScope) { ${newScopeId} = parentScope; };
            scopedAspectPolicies =
              _:
              let
                all = state.scopedAspectPolicies null;
                parentPolicies = all.${parentScope} or { };
              in
              all // { ${newScopeId} = (all.${newScopeId} or { }) // parentPolicies; };
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
