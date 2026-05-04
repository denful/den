# Handles: resolve-schema-entity
# Entity resolution: push scope, resolve entity, walk tree,
# drain deferred, propagate forwards, pop scope.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx.handlers) constantHandler;
  inherit (den.lib.aspects.fx.aspect) aspectToEffect;
  inherit (den.lib.aspects.fx.pipeline) mkScopeId;

  # Build scope handler set for entity context.
  mkScopeHandlers =
    scopedCtx: entityClass:
    constantHandler (scopedCtx // lib.optionalAttrs (entityClass != null) { class = entityClass; });

  # Push scope: set currentScope, register context, inherit parent policies.
  pushScope =
    scopedCtx: entityClass: newScopeId:
    fx.effects.state.modify (
      st:
      let
        parentScope = st.currentScope;
        isSameScope = newScopeId == parentScope;
      in
      st // {
        currentScope = newScopeId;
        scopeContexts = _: (st.scopeContexts null) // { ${newScopeId} = scopedCtx; };
        scopeParent =
          _: (st.scopeParent null) // lib.optionalAttrs (!isSameScope) { ${newScopeId} = parentScope; };
        scopedAspectPolicies = _:
          let
            all = st.scopedAspectPolicies null;
            parentPolicies = all.${parentScope} or { };
          in
          all // { ${newScopeId} = (all.${newScopeId} or { }) // parentPolicies; };
      }
    );

  # Copy parent-scope deferred items into a child scope (fan-out support).
  copyDeferredToScope =
    parentScope: newScopeId:
    fx.effects.state.modify (
      st:
      let
        allScoped = (st.scopedDeferredIncludes or (_: { })) null;
        parentItems = allScoped.${parentScope} or [ ];
      in
      if parentItems == [ ] then st
      else st // {
        scopedDeferredIncludes = _: allScoped // {
          ${newScopeId} = (allScoped.${newScopeId} or [ ]) ++ parentItems;
        };
      }
    );

  # Strip stale __ctxId from aspects (prevents identity mismatches in fresh scope).
  stripCtxId =
    a:
    if builtins.isAttrs a then
      (builtins.removeAttrs a [ "__ctxId" ])
      // lib.optionalAttrs (a ? includes) { includes = map stripCtxId (a.includes or [ ]); }
    else a;

  # Merge policy/resolve includes into raw entity.
  mergeEntityIncludes =
    rawEntity: includeAspects: policyIncludes: resolveIncludes:
    rawEntity // {
      includes =
        (rawEntity.includes or [ ])
        ++ map stripCtxId includeAspects
        ++ map stripCtxId policyIncludes
        ++ map stripCtxId resolveIncludes;
    };

  # Walk deferred aspects after entity resolution, collecting results.
  walkDeferred =
    scopeHandlersForCtx: prevResults: childResult: satisfiable:
    builtins.foldl' (
      acc': deferred:
      fx.bind acc' (
        prev:
        fx.bind (aspectToEffect (deferred.child // { __scopeHandlers = scopeHandlersForCtx; })) (
          resolved: fx.pure (prev ++ [ resolved ])
        )
      )
    ) (fx.pure (prevResults ++ [ childResult ])) satisfiable;

  # Propagate root-scope complex routes to child scope.
  propagateRootRoutes =
    newScopeId: restoreScope: allResults:
    fx.bind fx.effects.state.get (
      postWalkState:
      let
        rootSid = postWalkState.rootScopeId;
        rootRoutes = (postWalkState.scopedRoutes null).${rootSid} or [ ];
        childClasses = (postWalkState.scopedClassImports null).${newScopeId} or { };
        complexRootRoutes = builtins.filter (r: r.__complexForward or false) rootRoutes;
        childRoutes = map (r: r // { sourceScopeId = newScopeId; }) (
          builtins.filter (r: childClasses ? ${r.fromClass}) complexRootRoutes
        );
      in
      if childRoutes == [ ] then
        fx.bind restoreScope (_: fx.pure allResults)
      else
        fx.bind (fx.effects.state.modify (st: st // {
          scopedRoutes = _:
            let all = st.scopedRoutes null;
            in all // { ${newScopeId} = (all.${newScopeId} or [ ]) ++ childRoutes; };
        })) (_: fx.bind restoreScope (_: fx.pure allResults))
    );

  # Resolve entity tree within scope: resolve-entity → walk → drain → propagate.
  resolveEntityInScope =
    scopeHandlersForCtx: scopedCtx: param: prevResults: newScopeId: restoreScope:
    fx.effects.scope.provide scopeHandlersForCtx (
      fx.bind (fx.send "resolve-entity" { kind = param.targetKind; }) (
        rawEntity:
        let
          entity = mergeEntityIncludes rawEntity param.includeAspects param.policyIncludes param.resolveIncludes;
        in
        fx.bind (aspectToEffect entity) (
          childResult:
          fx.bind (fx.send "drain-deferred" scopedCtx) (
            satisfiable:
            fx.bind (walkDeferred scopeHandlersForCtx prevResults childResult satisfiable) (
              allResults: propagateRootRoutes newScopeId restoreScope allResults
            )
          )
        )
      )
    );

  resolveSchemaEntityHandler = {
    "resolve-schema-entity" =
      { param, state }:
      let
        scope = state.currentScope;
        newScopeId = mkScopeId param.scopedCtx;
        scopeHandlersForCtx = mkScopeHandlers param.scopedCtx param.entityClass;
        restoreScope = fx.effects.state.modify (st: st // { currentScope = scope; });
      in
      {
        resume =
          fx.bind (pushScope param.scopedCtx param.entityClass newScopeId) (_:
            fx.bind (copyDeferredToScope scope newScopeId) (_:
              resolveEntityInScope scopeHandlersForCtx param.scopedCtx param param.prevResults newScopeId restoreScope
            )
          );
        inherit state;
      };
  };

in
{
  inherit resolveSchemaEntityHandler;
}
