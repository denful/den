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
      let
        prevContexts = state.scopeContexts null;
        prevParent = state.scopeParent null;
        prevPolicies = state.scopedAspectPolicies null;
        prevEntityClass = (state.scopeEntityClass or (_: { })) null;
        prevEntityKind = (state.scopeEntityKind or (_: { })) null;
        prevSourcePolicy = (state.scopeSourcePolicy or (_: { })) null;
        updatedContexts = prevContexts // {
          ${newScopeId} = scopedCtx;
        };
        updatedParent = prevParent // lib.optionalAttrs (!isSameScope) { ${newScopeId} = parentScope; };
        updatedPolicies = prevPolicies // {
          ${newScopeId} = prevPolicies.${newScopeId} or { };
        };
        updatedEntityClass =
          prevEntityClass // lib.optionalAttrs (entityClass != null) { ${newScopeId} = entityClass; };
        updatedEntityKind =
          prevEntityKind // lib.optionalAttrs (entityKind != null) { ${newScopeId} = entityKind; };
        updatedSourcePolicy =
          prevSourcePolicy
          // lib.optionalAttrs (sourcePolicyName != null) { ${newScopeId} = sourcePolicyName; };
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
            inLateDispatch = false;
            inLateDispatchStack = (state.inLateDispatchStack or [ ]) ++ [ (state.inLateDispatch or false) ];
            scopeContexts = _: updatedContexts;
            scopeParent = _: updatedParent;
            scopedAspectPolicies = _: updatedPolicies;
            scopeEntityClass = _: updatedEntityClass;
            scopeEntityKind = _: updatedEntityKind;
            scopeSourcePolicy = _: updatedSourcePolicy;
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
