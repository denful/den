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

  # Propagate root-scope complex routes to a child scope.
  # Complex routes (those with __complexForward) registered at root scope
  # need child-scope copies so applyRoutes can read per-scope source modules.
  propagateRootRoutes =
    newScopeId: restoreScope: allResults:
    fx.bind (fx.effects.state.get) (
      postWalkState:
      let
        rootSid = postWalkState.rootScopeId;
        rootRoutes = (postWalkState.scopedRoutes null).${rootSid} or [ ];
        childClasses = (postWalkState.scopedClassImports null).${newScopeId} or { };
        # Only propagate complex routes — simple routes don't need per-scope source.
        complexRootRoutes = builtins.filter (r: r.__complexForward or false) rootRoutes;
        relevantRoutes = builtins.filter (r: childClasses ? ${r.fromClass}) complexRootRoutes;
        childRoutes = map (r: r // { sourceScopeId = newScopeId; }) relevantRoutes;
      in
      if childRoutes == [ ] then
        fx.bind restoreScope (_: fx.pure allResults)
      else
        fx.bind (fx.effects.state.modify (
          st:
          st
          // {
            scopedRoutes =
              _:
              let
                all = st.scopedRoutes null;
              in
              all // { ${newScopeId} = (all.${newScopeId} or [ ]) ++ childRoutes; };
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
          # Copy parent-scope deferred items into the new child scope.
          # This enables fan-out: { host, user } deferred at host scope
          # gets a fresh copy in each user scope, drained independently.
          fx.bind
            (fx.effects.state.modify (
              st:
              let
                allScoped = (st.scopedDeferredIncludes or (_: { })) null;
                parentItems = allScoped.${scope} or [ ];
              in
              if parentItems == [ ] then
                st
              else
                st
                // {
                  scopedDeferredIncludes =
                    _:
                    allScoped
                    // {
                      ${newScopeId} = (allScoped.${newScopeId} or [ ]) ++ parentItems;
                    };
                }
            ))
            (
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
                      ) (allResults: propagateRootRoutes newScopeId scopeTransition.restoreScope allResults)
                    )
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
