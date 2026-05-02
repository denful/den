# Handles: resolve-schema-entity
# Full entity resolution: push scope, resolve entity, walk tree,
# drain deferred, propagate forwards, pop scope.
{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  inherit (den.lib.aspects.fx.handlers) constantHandler;
  inherit (den.lib.aspects.fx.aspect) aspectToEffect;
  inherit (den.lib.aspects.fx.pipeline) mkScopeId;

  # Build scope transition operations for a schema effect.
  mkScopeTransition =
    scope: scopedCtx: entityClass: newScopeId:
    let
      scopeHandlersForCtx = constantHandler (
        scopedCtx // lib.optionalAttrs (entityClass != null) { class = entityClass; }
      );
      setScope = fx.effects.state.modify (
        st:
        let
          parentScope = st.currentScope;
          isSameScope = newScopeId == parentScope;
        in
        st
        // {
          currentScope = newScopeId;
          scopeContexts = _: (st.scopeContexts null) // { ${newScopeId} = scopedCtx; };
          scopeParent =
            _: (st.scopeParent null) // lib.optionalAttrs (!isSameScope) { ${newScopeId} = parentScope; };
          scopedAspectPolicies =
            _:
            let
              all = st.scopedAspectPolicies null;
              parentPolicies = all.${parentScope} or { };
            in
            all // { ${newScopeId} = (all.${newScopeId} or { }) // parentPolicies; };
        }
      );
      restoreScope = fx.effects.state.modify (st: st // { currentScope = scope; });
    in
    {
      inherit scopeHandlersForCtx setScope restoreScope;
    };

  # Propagate root-scope forward specs to a child scope.
  propagateRootForwards =
    newScopeId: restoreScope: allResults:
    fx.bind (fx.effects.state.get) (
      postWalkState:
      let
        rootSid = postWalkState.rootScopeId;
        rootForwards = (postWalkState.scopedForwardSpecs null).${rootSid} or [ ];
        childClasses = (postWalkState.scopedClassImports null).${newScopeId} or { };
        relevantForwards = builtins.filter (fwd: childClasses ? ${fwd.fromClass}) rootForwards;
        childForwards = map (fwd: fwd // { sourceScopeId = newScopeId; }) relevantForwards;
      in
      if childForwards == [ ] then
        fx.bind restoreScope (_: fx.pure allResults)
      else
        fx.bind (fx.effects.state.modify (
          st:
          st
          // {
            scopedForwardSpecs =
              _:
              let
                all = st.scopedForwardSpecs null;
              in
              all // { ${newScopeId} = (all.${newScopeId} or [ ]) ++ childForwards; };
          }
        )) (_: fx.bind restoreScope (_: fx.pure allResults))
    );

  # Walk deferred aspects after entity resolution.
  walkDeferred =
    scopeHandlersForCtx: ctxNames: prevResults: childResult: satisfiable:
    builtins.foldl' (
      acc': deferred:
      fx.bind acc' (
        prev:
        let
          deferredTagged = deferred.child // {
            __scopeHandlers = scopeHandlersForCtx;
            __ctxId = ctxNames;
          };
        in
        fx.bind (aspectToEffect deferredTagged) (resolved: fx.pure (prev ++ [ resolved ]))
      )
    ) (fx.pure (prevResults ++ [ childResult ])) satisfiable;

  resolveSchemaEntityHandler = {
    "resolve-schema-entity" =
      { param, state }:
      let
        inherit (param)
          targetKind
          scopedCtx
          entityClass
          includeAspects
          policyIncludes
          resolveIncludes
          ctxNames
          prevResults
          ;
        scope = state.currentScope;
        newScopeId = mkScopeId scopedCtx;
        scopeTransition = mkScopeTransition scope scopedCtx entityClass newScopeId;
      in
      {
        resume = fx.bind scopeTransition.setScope (
          _:
          fx.effects.scope.provide scopeTransition.scopeHandlersForCtx (
            fx.bind (fx.send "resolve-entity" { kind = targetKind; }) (
              rawEntity:
              let
                entity = rawEntity // {
                  includes = (rawEntity.includes or [ ]) ++ includeAspects ++ policyIncludes ++ resolveIncludes;
                };
              in
              fx.bind (aspectToEffect entity) (
                childResult:
                fx.bind (fx.send "drain-deferred" scopedCtx) (
                  satisfiable:
                  fx.bind (walkDeferred scopeTransition.scopeHandlersForCtx ctxNames prevResults childResult
                    satisfiable
                  ) (allResults: propagateRootForwards newScopeId scopeTransition.restoreScope allResults)
                )
              )
            )
          )
        );
        inherit state;
      };
  };

in
{
  inherit resolveSchemaEntityHandler;
}
