# Effect handler: push-scope
# Atomically sets currentScope, scopeContexts, scopeParent, and inherits
# scopedAspectPolicies. Deferred includes are NOT inherited to child scopes:
# entity-kind args are classified synchronously in bind (fan-out/inert/ctx),
# never carried cross-scope. Non-entity (pipe/enrichment) deferred includes are
# drained same-scope (drain.nix / resolve.nix baseDrain / scope-widen).
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
        # A push that lands on its parent's id adds no node: a routing kind's
        # push (`flake-system`, the microvm template's `microvm-host`) is context
        # belonging to its nearest entity ancestor, and a push of a record the
        # parent already binds (a `den.default` policy re-resolving `{ host }`
        # below where it first fired) re-enters that node. Neither overwrites
        # the scope's kind, entity link or isolation mark. An entity push of a
        # new record that adds no nameable key would have to share its parent's
        # node, so it is refused.
        isEntityKind = entityKind != null && (den.schema.${entityKind}.isEntity or false);
        pushedHash = if entityKind == null then null else (scopedCtx.${entityKind} or { }).id_hash or null;
        parentCtx = (state.scopeContexts null).${parentScope} or { };
        isReentry = pushedHash != null && (parentCtx.${entityKind} or { }).id_hash or null == pushedHash;
        checkedScopeId =
          if isSameScope && isEntityKind && !isReentry then
            throw "den: entity kind '${entityKind}' was resolved at scope '${parentScope}' with no binding that names it, so it has no scope of its own. Bind its record under `${entityKind}` in the resolve (e.g. `resolve.to \"${entityKind}\" { ${entityKind} = <record>; }`)."
          else
            newScopeId;
        scopeHandlers = constantHandler (
          scopedCtx // lib.optionalAttrs (entityClass != null) { class = entityClass; }
        );
      in
      let
        prevContexts = state.scopeContexts null;
        prevParent = state.scopeParent null;
        prevPolicies = state.scopedAspectPolicies null;
        prevEntityClass = (state.scopeEntityClass or (_: { })) null;
        prevEntityKind = (state.scopeEntityKind or (_: { })) null;
        prevSourcePolicy = (state.scopeSourcePolicy or (_: { })) null;
        prevIsolated = (state.scopeIsolated or (_: { })) null;
        prevScopeByEntity = (state.scopeByEntity or (_: { })) null;
        updatedContexts = prevContexts // {
          ${newScopeId} = prevContexts.${newScopeId} or scopedCtx;
        };
        # Spec→scope link: record the entity scope this push created, keyed by
        # (parentScope, id_hash). The instantiate spec — registered at the same
        # parent scope and carrying the same entity record — resolves its scope
        # via this link directly (no post-hoc name-infix reconstruction).
        # Only entity scopes (entityKind set, record carries id_hash) are linked.
        entityRecord = if entityKind == null then null else scopedCtx.${entityKind} or null;
        entityIdHash = if entityRecord == null then null else entityRecord.id_hash or null;
        updatedScopeByEntity =
          prevScopeByEntity
          // lib.optionalAttrs (entityIdHash != null && !isSameScope) {
            "${parentScope}\n${entityIdHash}" = newScopeId;
          };
        updatedParent = prevParent // lib.optionalAttrs (!isSameScope) { ${newScopeId} = parentScope; };
        updatedPolicies = prevPolicies // {
          ${newScopeId} = prevPolicies.${newScopeId} or { };
        };
        updatedEntityClass =
          prevEntityClass // lib.optionalAttrs (entityClass != null) { ${newScopeId} = entityClass; };
        updatedEntityKind =
          prevEntityKind
          // lib.optionalAttrs (entityKind != null && !isSameScope) { ${newScopeId} = entityKind; };
        updatedSourcePolicy =
          prevSourcePolicy
          // lib.optionalAttrs (sourcePolicyName != null) { ${newScopeId} = sourcePolicyName; };
        isolatedKind = entityKind != null && (den.schema.${entityKind}.isolated or false);
        updatedIsolated =
          prevIsolated // lib.optionalAttrs (isolatedKind && !isSameScope) { ${newScopeId} = true; };
      in
      {
        resume = {
          inherit scopeHandlers;
          scopeId = checkedScopeId;
        };
        state = state // {
          currentScope = checkedScopeId;
          inLateDispatch = false;
          inLateDispatchStack = (state.inLateDispatchStack or [ ]) ++ [ (state.inLateDispatch or false) ];
          scopeContexts = _: updatedContexts;
          scopeParent = _: updatedParent;
          scopedAspectPolicies = _: updatedPolicies;
          scopeEntityClass = _: updatedEntityClass;
          scopeEntityKind = _: updatedEntityKind;
          scopeSourcePolicy = _: updatedSourcePolicy;
          scopeIsolated = _: updatedIsolated;
          scopeByEntity = _: updatedScopeByEntity;
        };
      };
  };
in
{
  inherit pushScopeHandler;
}
