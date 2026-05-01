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
  identity = den.lib.aspects.fx.identity;

  # Context identity string — used for ctx-seen dedup keys.
  mkCtxId =
    ctx:
    lib.concatStringsSep "," (
      lib.sort (a: b: a < b) (
        map (
          attrName:
          let
            attrVal = ctx.${attrName};
          in
          if builtins.isAttrs attrVal && attrVal ? name then
            attrVal.name
          else if builtins.isString attrVal then
            attrVal
          else if builtins.isInt attrVal || builtins.isFloat attrVal then
            toString attrVal
          else
            attrName
        ) (builtins.attrNames ctx)
      )
    );

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

        # Process include/exclude effects via existing handlers, collecting results.
        emitIncludes =
          effects:
          builtins.foldl' (
            acc: e:
            fx.bind acc (
              prev:
              fx.bind (fx.send "emit-include" {
                child = e.value;
                idx = null;
              }) (r: fx.pure (prev ++ r))
            )
          ) (fx.pure [ ]) effects;

        emitExcludes =
          effects:
          builtins.foldl' (
            acc: e:
            fx.bind acc (
              _:
              fx.send "register-constraint" {
                type = "exclude";
                scope = "subtree";
                identity = identity.pathKey (identity.aspectPath e.value);
                owner = "policy";
              }
            )
          ) (fx.pure null) effects;

        emitRoutes =
          effects:
          builtins.foldl' (acc: e: fx.bind acc (_: fx.send "register-route" e.value)) (fx.pure null) effects;

        emitInstantiates =
          effects:
          builtins.foldl' (
            acc: e: fx.bind acc (_: fx.send "register-instantiate" e.value)
          ) (fx.pure null) effects;

        # Process schema resolve effects: ctx-seen dedup, push scope, walk entity, pop scope.
        # includeAspects: list of aspects from policy include effects, injected into
        # each resolved entity's includes so they resolve in the scoped context.
        processSchemaResolves =
          includeAspects: schemaEffects: enrichedCtx:
          let
            isFanOut = builtins.length schemaEffects > 1;
          in
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
                ctxNames = mkCtxId scopedCtx;
                ctxKey = if isFanOut then "${targetKind}/{${ctxNames}}" else targetKind;
                newScopeId = mkScopeId scopedCtx;
                scopeHandlers = constantHandler scopedCtx;

                # Set scope — save parentScope, set currentScope to child.
                setScope = fx.effects.state.modify (
                  st:
                  let
                    parentScope = st.currentScope;
                  in
                  st
                  // {
                    currentScope = newScopeId;
                    scopeContexts = _: (st.scopeContexts null) // { ${newScopeId} = scopedCtx; };
                    scopeParent = _: (st.scopeParent null) // { ${newScopeId} = parentScope; };
                    scopedAspectPolicies =
                      _:
                      let
                        all = st.scopedAspectPolicies null;
                        parentPolicies = all.${parentScope} or { };
                      in
                      all // { ${newScopeId} = (all.${newScopeId} or { }) // parentPolicies; };
                  }
                );

                # Restore scope — set currentScope back to parent.
                restoreScope = fx.effects.state.modify (
                  st:
                  st
                  // {
                    currentScope = scope;
                  }
                );

                # Full entity resolution: push scope, resolve entity, walk tree, drain deferred, pop.
                fullResolution = fx.bind setScope (
                  _:
                  fx.bind (fx.send "resolve-entity" { kind = targetKind; }) (
                    rawEntity:
                    let
                      entity = rawEntity // {
                        includes = (rawEntity.includes or [ ]) ++ includeAspects;
                      };
                    in
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
                                    __ctxId = ctxNames;
                                  };
                                in
                                fx.bind (aspectToEffect deferredTagged) (resolved: fx.pure (prev ++ [ resolved ]))
                              )
                            ) (fx.pure (prevResults ++ [ childResult ])) satisfiable)
                            (allResults: fx.bind restoreScope (_: fx.pure allResults))
                        )
                      )
                    )
                  )
                );

                # Supplemental: emit only new aspects as includes (entity already resolved).
                supplementalResolution =
                  newAspectValues:
                  builtins.foldl' (
                    sAcc: aspect:
                    fx.bind sAcc (
                      sPrev:
                      fx.bind (fx.send "emit-include" {
                        child = aspect;
                        idx = null;
                        __parentScopeHandlers = scopeHandlers;
                        __parentCtxId = ctxNames;
                      }) (_: fx.pure sPrev)
                    )
                  ) (fx.pure prevResults) newAspectValues;

                policyAspectPaths = map (a: identity.pathKey (identity.aspectPath a)) includeAspects;
              in
              # ctx-seen dedup: skip re-resolution of same entity context.
              fx.bind
                (fx.send "ctx-seen" {
                  key = ctxKey;
                  aspects = policyAspectPaths;
                  aspectValues = includeAspects;
                })
                (
                  { isFirst, newAspectValues }:
                  if isFirst then
                    fullResolution
                  else if newAspectValues != [ ] then
                    supplementalResolution newAspectValues
                  else
                    fx.pure prevResults
                )
            )
          ) (fx.pure [ ]) schemaEffects;

        # Fixed-point iteration: dispatch, collect enrichment, re-dispatch on widen.
        # Accumulator record for non-enrichment effects across iterations.
        emptyAcc = {
          schemaEffects = [ ];
          includeEffects = [ ];
          excludeEffects = [ ];
          routeEffects = [ ];
          instantiateEffects = [ ];
        };

        iterate =
          iteration: accEnrichment: accEffects: firedPolicies: currentResolveCtx:
          let
            dispatched = mkDispatch firedPolicies currentResolveCtx;
            # Filter out already-fired policies.
            newFiredNames = builtins.filter (n: !builtins.elem n firedPolicies) dispatched.firedNames;
            updatedFired = firedPolicies ++ newFiredNames;
            # Only enrichment keys not already in accumulated enrichment count as widening.
            newEnrichKeys = builtins.filter (k: !accEnrichment ? ${k}) (
              builtins.attrNames dispatched.enrichment
            );
            # Accumulate non-enrichment effects from this iteration.
            combinedEffects = {
              schemaEffects = accEffects.schemaEffects ++ dispatched.schemaEffects;
              includeEffects = accEffects.includeEffects ++ dispatched.includeEffects;
              excludeEffects = accEffects.excludeEffects ++ dispatched.excludeEffects;
              routeEffects = accEffects.routeEffects ++ dispatched.routeEffects;
              instantiateEffects = accEffects.instantiateEffects ++ dispatched.instantiateEffects;
            };
          in
          if newEnrichKeys == [ ] then
            # Stable — process all accumulated non-enrichment effects.
            let
              enrichedCtx = currentCtx // accEnrichment // dispatched.enrichment;
              includeAspects = map (e: e.value) combinedEffects.includeEffects;
              hasSchemaResolves = combinedEffects.schemaEffects != [ ];
            in
            fx.bind (emitExcludes combinedEffects.excludeEffects) (
              _:
              fx.bind (emitRoutes combinedEffects.routeEffects) (
                _:
                fx.bind (emitInstantiates combinedEffects.instantiateEffects) (
                  _:
                  if hasSchemaResolves then
                    processSchemaResolves includeAspects combinedEffects.schemaEffects enrichedCtx
                  else
                    emitIncludes combinedEffects.includeEffects
                )
              )
            )
          else if iteration >= maxIterations then
            throw "den: dispatch-policies enrichment iteration exceeded ${toString maxIterations} — likely a cycle (${entityKind})"
          else
            # Widen context and re-dispatch.
            let
              combinedEnrichment = accEnrichment // dispatched.enrichment;
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
                )) (_: iterate (iteration + 1) combinedEnrichment combinedEffects updatedFired nextResolveCtx)
              );

        resolveCtx = traits // currentCtx // { __entityKind = entityKind; };
        # Dedup: if this entity+scope was already dispatched, skip.
        dispatchKey = "${entityKind}@${scope}";
        alreadyDispatched = builtins.elem dispatchKey ((state.dispatchedPolicies or (_: [ ])) null);
      in
      {
        resume =
          if alreadyDispatched then
            fx.pure [ ]
          else
            fx.bind (fx.effects.state.modify (
              st:
              st
              // {
                dispatchedPolicies = _: ((st.dispatchedPolicies or (_: [ ])) null) ++ [ dispatchKey ];
              }
            )) (_: iterate 0 { } emptyAcc [ ] resolveCtx);
        inherit state;
      };
  };

in
{
  inherit dispatchPoliciesHandler;
}
