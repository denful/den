{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  inherit (den.lib.aspects.fx.aspect) aspectToEffect;
  inherit (den.lib.aspects.fx.handlers) constantHandler;
  inherit (den.lib.aspects.fx.pipeline) mkScopeId;
  inherit (den.lib.policyTypes) policyFnArgs;
  inherit (den.lib.synthesizePolicies) resolveArgsSatisfied;

  # Schema entity kinds — used to classify resolve effects.
  schemaKinds = builtins.filter (
    n: n != "conf" && !(lib.hasPrefix "_" n) && (den.schema.${n}.isEntity or false)
  ) (builtins.attrNames (den.schema or { }));

  # Classify a resolve effect into schema vs enrichment.
  classifyResolve =
    e:
    let
      keys = builtins.attrNames e.value;
      schemaKeys = builtins.filter (k: builtins.elem k schemaKinds) keys;
      enrichKeys = builtins.filter (k: !builtins.elem k schemaKinds) keys;
      hasTarget = e.__targetKind or null != null;
    in
    if hasTarget then
      {
        schema = e;
        enrichment = null;
      }
    else if schemaKeys == [ ] then
      {
        schema = null;
        enrichment = e.value;
      }
    else if enrichKeys == [ ] then
      {
        schema = e;
        enrichment = null;
      }
    else
      {
        schema = e // {
          value = lib.filterAttrs (k: _: builtins.elem k schemaKinds) e.value;
        };
        enrichment = lib.filterAttrs (k: _: !builtins.elem k schemaKinds) e.value;
      };

  maxIterations = 10;

  dispatchPoliciesHandler = {
    "dispatch-policies" =
      { param, state }:
      let
        ctx = param.ctx;
        entityKind = param.entityKind;
        scope = state.currentScope;
        currentCtx = if scope == null then ctx else (state.scopeContexts null).${scope} or ctx;

        # Merge traits into resolve context.
        traits = builtins.foldl' (acc: v: acc // v) { } (builtins.attrValues (state.scopedTraits null));
        traitNames = state.traitSchemas null;

        # Three policy sources.
        globalPolicies = den.policies or { };
        schemaPolicies = (den.schema.${entityKind} or { }).policies or { };
        allDirectPolicies = globalPolicies // schemaPolicies;

        # Flatten aspect policies from all scopes.
        aspectPolicies = builtins.foldl' (acc: v: acc // v) { } (
          builtins.attrValues ((state.scopedAspectPolicies or (_: { })) null)
        );

        # Dispatch all direct (global + schema) policies against a context.
        dispatchDirect =
          firedPolicies: resolveCtx:
          lib.concatLists (
            lib.mapAttrsToList (
              name: policy:
              let
                argsOk = resolveArgsSatisfied policy resolveCtx;
              in
              if !argsOk || builtins.elem name firedPolicies then
                [ ]
              else
                let
                  rawEffects =
                    let
                      result = policy resolveCtx;
                    in
                    if builtins.isList result then result else [ result ];
                in
                if rawEffects == [ ] then
                  [ ]
                else
                  [
                    {
                      policyName = name;
                      effects = rawEffects;
                    }
                  ]
            ) allDirectPolicies
          );

        # Dispatch aspect policies against a context.
        dispatchAspect =
          firedPolicies: resolveCtx:
          let
            entries = lib.attrsToList aspectPolicies;
            matching = builtins.filter (
              e:
              let
                fargs = policyFnArgs e.value.fn;
                requiredArgs = builtins.filter (k: !fargs.${k}) (builtins.attrNames fargs);
              in
              builtins.all (k: resolveCtx ? ${k} || traitNames ? ${k}) requiredArgs
              && !builtins.elem e.name firedPolicies
            ) entries;
          in
          map (
            entry:
            let
              rawEffects =
                let
                  result = entry.value.fn resolveCtx;
                in
                if builtins.isList result then result else [ result ];
            in
            {
              policyName = entry.name;
              effects = rawEffects;
            }
          ) matching;

        # Combined dispatch returning classified results.
        mkDispatch =
          firedPolicies: resolveCtx:
          let
            allResults = dispatchDirect firedPolicies resolveCtx ++ dispatchAspect firedPolicies resolveCtx;

            # Classify effects per policy result.
            classified = map (
              r:
              let
                resolveEffects = builtins.filter (
                  e: builtins.isAttrs e && (e.__policyEffect or "") == "resolve" && e.value != { }
                ) r.effects;
                includeEffects = builtins.filter (
                  e: builtins.isAttrs e && (e.__policyEffect or "") == "include"
                ) r.effects;
                excludeEffects = builtins.filter (
                  e: builtins.isAttrs e && (e.__policyEffect or "") == "exclude"
                ) r.effects;
                routeEffects = builtins.filter (
                  e: builtins.isAttrs e && (e.__policyEffect or "") == "route"
                ) r.effects;
                instantiateEffects = builtins.filter (
                  e: builtins.isAttrs e && (e.__policyEffect or "") == "instantiate"
                ) r.effects;

                resolveClassified = map classifyResolve resolveEffects;
                schemaEffects = builtins.filter (c: c.schema != null) resolveClassified;
                enrichEffects = builtins.filter (c: c.enrichment != null) resolveClassified;
                mergedEnrichment = builtins.foldl' (acc: c: acc // c.enrichment) { } enrichEffects;
              in
              {
                inherit (r) policyName;
                inherit
                  schemaEffects
                  mergedEnrichment
                  includeEffects
                  excludeEffects
                  routeEffects
                  instantiateEffects
                  ;
              }
            ) allResults;

            allEnrichment = builtins.foldl' (acc: r: acc // r.mergedEnrichment) { } classified;
            allSchemaEffects = builtins.concatMap (r: r.schemaEffects) classified;
            allIncludeEffects = builtins.concatMap (r: r.includeEffects) classified;
            allExcludeEffects = builtins.concatMap (r: r.excludeEffects) classified;
            allRouteEffects = builtins.concatMap (
              r: map (re: re // { __routePolicyName = r.policyName; }) r.routeEffects
            ) classified;
            allInstantiateEffects = builtins.concatMap (
              r: map (ie: ie // { __instantiatePolicyName = r.policyName; }) r.instantiateEffects
            ) classified;
            # Track which policies fired (had any effects).
            firedNames = map (r: r.policyName) (
              builtins.filter (
                r:
                r.schemaEffects != [ ]
                || r.mergedEnrichment != { }
                || r.includeEffects != [ ]
                || r.excludeEffects != [ ]
                || r.routeEffects != [ ]
                || r.instantiateEffects != [ ]
              ) classified
            );
          in
          {
            enrichment = allEnrichment;
            schemaEffects = allSchemaEffects;
            includeEffects = allIncludeEffects;
            excludeEffects = allExcludeEffects;
            routeEffects = allRouteEffects;
            instantiateEffects = allInstantiateEffects;
            inherit firedNames;
          };

        # Process include/exclude effects via existing handlers.
        emitIncludes =
          effects:
          builtins.foldl' (acc: e: fx.bind acc (_: fx.send "include" e.value)) (fx.pure null) effects;

        emitExcludes =
          effects:
          builtins.foldl' (acc: e: fx.bind acc (_: fx.send "exclude" e.value)) (fx.pure null) effects;

        emitRoutes =
          effects:
          builtins.foldl' (acc: e: fx.bind acc (_: fx.send "register-route" e.value)) (fx.pure null) effects;

        emitInstantiates =
          effects:
          builtins.foldl' (
            acc: e: fx.bind acc (_: fx.send "register-instantiate" e.value)
          ) (fx.pure null) effects;

        # Process schema resolve effects: push scope, walk entity, pop scope.
        processSchemaResolves =
          schemaEffects: enrichedCtx:
          builtins.foldl' (
            acc: schemaEffect:
            fx.bind acc (
              prevResults:
              let
                # Determine target entity kind from the schema effect.
                keys = builtins.attrNames schemaEffect.schema.value;
                targetKind =
                  if schemaEffect.schema.__targetKind or null != null then
                    schemaEffect.schema.__targetKind
                  else
                    lib.findFirst (k: builtins.elem k schemaKinds) (
                      if keys != [ ] then builtins.head keys else entityKind
                    ) keys;
                # Build context for this schema resolve.
                resolveBindings = schemaEffect.schema.value;
                scopedCtx = enrichedCtx // resolveBindings;
                newScopeId = mkScopeId scopedCtx;
                scopeHandlers = constantHandler scopedCtx;

                pushScope = fx.effects.state.modify (
                  st:
                  let
                    parentScope = st.currentScope;
                  in
                  st
                  // {
                    currentScope = newScopeId;
                    scopeStack = _: (st.scopeStack null) ++ [ parentScope ];
                    scopeContexts = _: (st.scopeContexts null) // { ${newScopeId} = scopedCtx; };
                    scopeParent = _: (st.scopeParent null) // { ${newScopeId} = parentScope; };
                    scopeChildren =
                      _:
                      let
                        all = st.scopeChildren null;
                      in
                      all // { ${parentScope} = (all.${parentScope} or [ ]) ++ [ newScopeId ]; };
                    scopedAspectPolicies =
                      _:
                      let
                        all = st.scopedAspectPolicies null;
                        parentPolicies = all.${parentScope} or { };
                      in
                      all // { ${newScopeId} = (all.${newScopeId} or { }) // parentPolicies; };
                  }
                );

                popScope = fx.effects.state.modify (
                  st:
                  let
                    stack = st.scopeStack null;
                  in
                  st
                  // {
                    currentScope = lib.last stack;
                    scopeStack = _: lib.init stack;
                  }
                );
              in
              fx.bind pushScope (
                _:
                fx.bind (fx.send "resolve-entity" { kind = targetKind; }) (
                  entity:
                  fx.bind (aspectToEffect entity) (
                    childResult:
                    fx.bind (fx.send "drain-deferred" scopedCtx) (
                      satisfiable:
                      fx.bind (fx.send "drain-dead-letters" null) (
                        _:
                        fx.bind
                          (builtins.foldl' (
                            acc': deferred:
                            fx.bind acc' (
                              prev:
                              let
                                deferredTagged = deferred.child // {
                                  __scopeHandlers = scopeHandlers;
                                  __ctxId = lib.concatStringsSep "," (
                                    lib.sort (a: b: a < b) (
                                      map (
                                        attrName:
                                        let
                                          attrVal = scopedCtx.${attrName};
                                        in
                                        if builtins.isAttrs attrVal && attrVal ? name then
                                          attrVal.name
                                        else if builtins.isString attrVal then
                                          attrVal
                                        else if builtins.isInt attrVal || builtins.isFloat attrVal then
                                          toString attrVal
                                        else
                                          attrName
                                      ) (builtins.attrNames scopedCtx)
                                    )
                                  );
                                };
                              in
                              fx.bind (aspectToEffect deferredTagged) (resolved: fx.pure (prev ++ [ resolved ]))
                            )
                          ) (fx.pure (prevResults ++ [ childResult ])) satisfiable)
                          (allResults: fx.bind popScope (_: fx.pure allResults))
                      )
                    )
                  )
                )
              )
            )
          ) (fx.pure [ ]) schemaEffects;

        # Fixed-point iteration: dispatch, collect enrichment, re-dispatch on widen.
        iterate =
          iteration: accEnrichment: firedPolicies: currentResolveCtx:
          let
            dispatched = mkDispatch firedPolicies currentResolveCtx;
            # Filter out already-fired policies.
            newFiredNames = builtins.filter (n: !builtins.elem n firedPolicies) dispatched.firedNames;
            updatedFired = firedPolicies ++ newFiredNames;
            # Only enrichment keys not already in accumulated enrichment count as widening.
            newEnrichKeys = builtins.filter (k: !accEnrichment ? ${k}) (
              builtins.attrNames dispatched.enrichment
            );
          in
          if newEnrichKeys == [ ] then
            # Stable — process all non-enrichment effects.
            let
              enrichedCtx = currentCtx // dispatched.enrichment;
            in
            fx.bind (emitIncludes dispatched.includeEffects) (
              _:
              fx.bind (emitExcludes dispatched.excludeEffects) (
                _:
                fx.bind (emitRoutes dispatched.routeEffects) (
                  _:
                  fx.bind (emitInstantiates dispatched.instantiateEffects) (
                    _: processSchemaResolves dispatched.schemaEffects enrichedCtx
                  )
                )
              )
            )
          else if iteration >= maxIterations then
            throw "den: dispatch-policies enrichment iteration exceeded ${toString maxIterations} — likely a cycle (${entityKind})"
          else
            # Widen context and re-dispatch.
            let
              combinedEnrichment = dispatched.enrichment;
              enrichedCtx = currentCtx // combinedEnrichment;
              enrichHandlers = constantHandler combinedEnrichment;
              nextResolveCtx = traits // enrichedCtx // { __entityKind = entityKind; };
            in
            fx.bind
              (fx.effects.state.modify (
                st:
                st
                // {
                  scopeContexts = _: (st.scopeContexts null) // { ${st.currentScope} = enrichedCtx; };
                }
              ))
              (
                _:
                fx.bind (fx.effects.scope.provide enrichHandlers (
                  fx.bind (fx.send "drain-deferred" enrichedCtx) (
                    satisfiable:
                    fx.bind (fx.send "drain-dead-letters" null) (
                      _:
                      builtins.foldl' (
                        acc: deferred:
                        fx.bind acc (
                          _:
                          let
                            scopeHandlers = constantHandler enrichedCtx;
                            deferredTagged = deferred.child // {
                              __scopeHandlers = scopeHandlers;
                            };
                          in
                          fx.bind (aspectToEffect deferredTagged) (_: fx.pure null)
                        )
                      ) (fx.pure null) satisfiable
                    )
                  )
                )) (_: iterate (iteration + 1) (accEnrichment // dispatched.enrichment) updatedFired nextResolveCtx)
              );

        resolveCtx = traits // currentCtx // { __entityKind = entityKind; };
      in
      {
        resume = iterate 0 { } [ ] resolveCtx;
        inherit state;
      };
  };

in
{
  inherit dispatchPoliciesHandler;
}
