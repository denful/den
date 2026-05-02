{
  lib,
  den,
  ...
}:
{
  aspectToEffect,
  ctxFromHandlers,
}:
let
  fx = den.lib.fx;
  inherit (den.lib.aspects.fx.handlers) constantHandler;
  inherit (den.lib.synthesizePolicies) resolveArgsSatisfied;
  inherit (den.lib.policyTypes) policyFnArgs;
  inherit (den.lib.aspects.fx.pipeline) mkScopeId;
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
  policySchemaKinds = builtins.filter (
    n: n != "conf" && !(lib.hasPrefix "_" n) && (den.schema.${n}.isEntity or false)
  ) (builtins.attrNames (den.schema or { }));

  # Classify a resolve effect into schema vs enrichment.
  classifyResolve =
    e:
    let
      keys = builtins.attrNames e.value;
      schemaKeys = builtins.filter (k: builtins.elem k policySchemaKinds) keys;
      enrichKeys = builtins.filter (k: !builtins.elem k policySchemaKinds) keys;
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
          value = lib.filterAttrs (k: _: builtins.elem k policySchemaKinds) e.value;
        };
        enrichment = lib.filterAttrs (k: _: !builtins.elem k policySchemaKinds) e.value;
      };

  maxPolicyIterations = 10;

  # Dispatch global + schema policies against a context.
  dispatchDirect =
    allDirectPolicies: firedPolicies: resolveCtx:
    lib.concatLists (
      lib.mapAttrsToList (
        name: policy:
        if !resolveArgsSatisfied policy resolveCtx || builtins.elem name firedPolicies then
          [ ]
        else
          let
            result = policy resolveCtx;
            rawEffects = if builtins.isList result then result else [ result ];
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
    aspectPolicies: firedPolicies: resolveCtx:
    let
      entries = lib.attrsToList aspectPolicies;
      matching = builtins.filter (
        e:
        let
          fargs = policyFnArgs e.value.fn;
          requiredArgs = builtins.filter (k: !fargs.${k}) (builtins.attrNames fargs);
        in
        builtins.all (k: resolveCtx ? ${k}) requiredArgs && !builtins.elem e.name firedPolicies
      ) entries;
    in
    map (
      entry:
      let
        result = entry.value.fn resolveCtx;
        rawEffects = if builtins.isList result then result else [ result ];
      in
      {
        policyName = entry.name;
        effects = rawEffects;
      }
    ) matching;

  # Extract effects of a given type from a policy result.
  filterEffect =
    kind: effects: builtins.filter (e: builtins.isAttrs e && (e.__policyEffect or "") == kind) effects;

  # Classify a single policy result into effect categories.
  classifyPolicyResult =
    r:
    let
      resolveEffects = builtins.filter (
        e: builtins.isAttrs e && (e.__policyEffect or "") == "resolve" && e.value != { }
      ) r.effects;
      resolveClassified = map classifyResolve resolveEffects;
    in
    {
      inherit (r) policyName;
      schemaEffects = builtins.filter (c: c.schema != null) resolveClassified;
      mergedEnrichment = builtins.foldl' (acc: c: acc // c.enrichment) { } (
        builtins.filter (c: c.enrichment != null) resolveClassified
      );
      includeEffects = filterEffect "include" r.effects;
      excludeEffects = filterEffect "exclude" r.effects;
      routeEffects = filterEffect "route" r.effects;
      instantiateEffects = filterEffect "instantiate" r.effects;
      provideEffects = filterEffect "provide" r.effects;
    };

  # Tag cross-provider schema effects with their paired includes.
  tagCrossProvider =
    r:
    let
      isCrossProvider =
        r.schemaEffects != [ ]
        && r.includeEffects != [ ]
        && builtins.any (se: se.schema.__targetKind or null != null) r.schemaEffects;
    in
    r // { inherit isCrossProvider; };

  # Check if a classified result has any effects.
  hasEffects =
    r:
    r.schemaEffects != [ ]
    || r.mergedEnrichment != { }
    || r.includeEffects != [ ]
    || r.excludeEffects != [ ]
    || r.routeEffects != [ ]
    || r.instantiateEffects != [ ]
    || r.provideEffects != [ ];

  # Collect all schema effects, attaching cross-provider includes.
  collectSchemaEffects =
    paired:
    builtins.concatMap (
      r:
      if r.isCrossProvider then
        map (se: se // { __policyIncludes = map (e: e.value) r.includeEffects; }) r.schemaEffects
      else
        r.schemaEffects
    ) paired;

  # Collect non-cross-provider include effects.
  collectIncludeEffects =
    paired: builtins.concatMap (r: if r.isCrossProvider then [ ] else r.includeEffects) paired;

  # Combined dispatch returning classified results.
  mkDispatch =
    allDirectPolicies: aspectPolicies: firedPolicies: resolveCtx:
    let
      allResults =
        dispatchDirect allDirectPolicies firedPolicies resolveCtx
        ++ dispatchAspect aspectPolicies firedPolicies resolveCtx;
      classified = map classifyPolicyResult allResults;
      paired = map tagCrossProvider classified;
    in
    {
      enrichment = builtins.foldl' (acc: r: acc // r.mergedEnrichment) { } classified;
      schemaEffects = collectSchemaEffects paired;
      includeEffects = collectIncludeEffects paired;
      excludeEffects = builtins.concatMap (r: r.excludeEffects) classified;
      routeEffects = builtins.concatMap (
        r: map (re: re // { __routePolicyName = r.policyName; }) r.routeEffects
      ) classified;
      instantiateEffects = builtins.concatMap (
        r: map (ie: ie // { __instantiatePolicyName = r.policyName; }) r.instantiateEffects
      ) classified;
      provideEffects = builtins.concatMap (
        r: map (pe: pe // { __providePolicyName = r.policyName; }) r.provideEffects
      ) classified;
      firedNames = map (r: r.policyName) (builtins.filter hasEffects classified);
    };

  # Emit policy include effects via existing handlers.
  policyEmitIncludes =
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

  # Emit policy exclude effects.
  policyEmitExcludes =
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

  # Emit policy route, instantiate, and provide effects.
  policyEmitEffects =
    routeEffects: instantiateEffects: provideEffects:
    fx.bind
      (builtins.foldl' (
        acc: e: fx.bind acc (_: fx.send "register-route" e.value)
      ) (fx.pure null) routeEffects)
      (
        _:
        fx.bind
          (builtins.foldl' (
            acc: e: fx.bind acc (_: fx.send "register-instantiate" e.value)
          ) (fx.pure null) instantiateEffects)
          (
            _:
            builtins.foldl' (
              acc: e: fx.bind acc (_: fx.send "register-provide" e.value)
            ) (fx.pure null) provideEffects
          )
      );

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

  # Full entity resolution: push scope, resolve entity, walk tree,
  # drain deferred, propagate forwards, pop scope.
  mkFullResolution =
    scopeTransition: includeAspects: policyIncludes: resolveIncludes: targetKind: scopedCtx: ctxNames: newScopeId: prevResults:
    fx.bind scopeTransition.setScope (
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

  # Emit new aspects as includes for already-seen contexts.
  mkSupplementalResolution =
    scopeHandlersForCtx: ctxNames: prevResults: newAspectValues:
    builtins.foldl' (
      sAcc: supAspect:
      fx.bind sAcc (
        sPrev:
        fx.bind (fx.send "emit-include" {
          child = supAspect;
          idx = null;
          __parentScopeHandlers = scopeHandlersForCtx;
          __parentCtxId = ctxNames;
        }) (_: fx.pure sPrev)
      )
    ) (fx.pure prevResults) newAspectValues;

  # Determine target entity kind from a schema effect.
  resolveTargetKind =
    entityKind: schemaEffect:
    let
      keys = builtins.attrNames schemaEffect.schema.value;
    in
    if schemaEffect.schema.__targetKind or null != null then
      schemaEffect.schema.__targetKind
    else
      lib.findFirst (k: builtins.elem k policySchemaKinds) (
        if keys != [ ] then builtins.head keys else entityKind
      ) keys;

  # Resolve entity class from schema bindings for scope handler override.
  resolveEntityClass =
    targetKind: resolveBindings:
    let
      entity = resolveBindings.${targetKind} or null;
      classes = if entity != null then entity.classes or null else null;
    in
    if classes != null && classes != [ ] then builtins.head classes else null;

  # Process a single schema resolve effect within the fold.
  processSingleResolve =
    entityKind: scope: enrichedCtx: includeAspects: isFanOut: prevResults: schemaEffect:
    let
      targetKind = resolveTargetKind entityKind schemaEffect;
      resolveBindings = schemaEffect.schema.value;
      scopedCtx = enrichedCtx // resolveBindings;
      ctxNames = mkCtxId scopedCtx;
      ctxKey = if isFanOut then "${targetKind}/{${ctxNames}}" else targetKind;
      newScopeId = mkScopeId scopedCtx;
      entityClass = resolveEntityClass targetKind resolveBindings;
      scopeTransition = mkScopeTransition scope scopedCtx entityClass newScopeId;
      policyIncludes = schemaEffect.__policyIncludes or [ ];
      resolveIncludes = schemaEffect.schema.includes or [ ];
      policyAspectPaths = map (a: identity.pathKey (identity.aspectPath a)) (
        includeAspects ++ policyIncludes ++ resolveIncludes
      );
    in
    fx.bind
      (fx.send "ctx-seen" {
        key = ctxKey;
        aspects = policyAspectPaths;
        aspectValues = includeAspects;
      })
      (
        { isFirst, newAspectValues }:
        if isFirst then
          mkFullResolution scopeTransition includeAspects policyIncludes resolveIncludes targetKind scopedCtx
            ctxNames
            newScopeId
            prevResults
        else if newAspectValues != [ ] then
          mkSupplementalResolution scopeTransition.scopeHandlersForCtx ctxNames prevResults newAspectValues
        else
          fx.pure prevResults
      );

  # Process schema resolve effects: ctx-seen dedup, push scope, walk entity, pop scope.
  processSchemaResolves =
    entityKind: scope: includeAspects: schemaEffects: enrichedCtx:
    let
      isFanOut = builtins.length schemaEffects > 1;
    in
    builtins.foldl' (
      acc: schemaEffect:
      fx.bind acc (
        prevResults:
        processSingleResolve entityKind scope enrichedCtx includeAspects isFanOut prevResults schemaEffect
      )
    ) (fx.pure [ ]) schemaEffects;

  # Empty accumulator for iteration.
  emptyAcc = {
    schemaEffects = [ ];
    includeEffects = [ ];
    excludeEffects = [ ];
    routeEffects = [ ];
    instantiateEffects = [ ];
    provideEffects = [ ];
  };

  # Merge new dispatch results into the accumulator.
  mergeEffects = accEffects: dispatched: {
    schemaEffects = accEffects.schemaEffects ++ dispatched.schemaEffects;
    includeEffects = accEffects.includeEffects ++ dispatched.includeEffects;
    excludeEffects = accEffects.excludeEffects ++ dispatched.excludeEffects;
    routeEffects = accEffects.routeEffects ++ dispatched.routeEffects;
    instantiateEffects = accEffects.instantiateEffects ++ dispatched.instantiateEffects;
    provideEffects = accEffects.provideEffects ++ dispatched.provideEffects;
  };

  # Emit final effects when enrichment has stabilized.
  emitFinalEffects =
    entityKind: scope: currentCtx: accEnrichment: dispatched: combinedEffects:
    let
      enrichedCtx = currentCtx // accEnrichment // dispatched.enrichment;
      includeAspects = map (e: e.value) combinedEffects.includeEffects;
      hasSchemaResolves = combinedEffects.schemaEffects != [ ];
    in
    fx.bind (policyEmitExcludes combinedEffects.excludeEffects) (
      _:
      fx.bind
        (policyEmitEffects combinedEffects.routeEffects combinedEffects.instantiateEffects
          combinedEffects.provideEffects
        )
        (
          _:
          if hasSchemaResolves then
            processSchemaResolves entityKind scope includeAspects combinedEffects.schemaEffects enrichedCtx
          else
            policyEmitIncludes combinedEffects.includeEffects
        )
    );

  # Drain deferred aspects after enrichment context widen.
  drainEnrichmentDeferred =
    enrichedCtx:
    fx.bind (fx.send "drain-deferred" enrichedCtx) (
      satisfiable:
      builtins.foldl' (
        acc: deferred:
        fx.bind acc (
          _:
          let
            deferScopeHandlers = constantHandler enrichedCtx;
            deferredTagged = deferred.child // {
              __scopeHandlers = deferScopeHandlers;
            };
          in
          fx.bind (aspectToEffect deferredTagged) (_: fx.pure null)
        )
      ) (fx.pure null) satisfiable
    );

  # Fixed-point iteration: dispatch, collect enrichment, re-dispatch on widen.
  iterate =
    allDirectPolicies: aspectPolicies: entityKind: scope: currentCtx: iteration: accEnrichment: accEffects: firedPolicies: currentResolveCtx:
    let
      dispatched = mkDispatch allDirectPolicies aspectPolicies firedPolicies currentResolveCtx;
      newFiredNames = builtins.filter (n: !builtins.elem n firedPolicies) dispatched.firedNames;
      updatedFired = firedPolicies ++ newFiredNames;
      newEnrichKeys = builtins.filter (k: !accEnrichment ? ${k}) (
        builtins.attrNames dispatched.enrichment
      );
      combinedEffects = mergeEffects accEffects dispatched;
    in
    if newEnrichKeys == [ ] then
      emitFinalEffects entityKind scope currentCtx accEnrichment dispatched combinedEffects
    else if iteration >= maxPolicyIterations then
      throw "den: installPolicies enrichment iteration exceeded ${toString maxPolicyIterations} — likely a cycle (${entityKind})"
    else
      let
        combinedEnrichment = accEnrichment // dispatched.enrichment;
        enrichedCtx = currentCtx // combinedEnrichment;
        enrichHandlers = constantHandler combinedEnrichment;
        nextResolveCtx = enrichedCtx // {
          __entityKind = entityKind;
        };
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
          fx.bind (fx.effects.scope.provide enrichHandlers (drainEnrichmentDeferred enrichedCtx)) (
            _:
            iterate allDirectPolicies aspectPolicies entityKind scope currentCtx (
              iteration + 1
            ) combinedEnrichment combinedEffects updatedFired nextResolveCtx
          )
        );

  # Entry point: read state, check dedup, call iterate.
  installPolicies =
    aspect:
    let
      entityKind = aspect.__entityKind;
      ctx = ctxFromHandlers (aspect.__scopeHandlers or { });
    in
    fx.bind fx.effects.state.get (
      state:
      let
        scope = state.currentScope;
        currentCtx = if scope == null then ctx else (state.scopeContexts null).${scope} or ctx;
        dispatchKey = "${entityKind}@${scope}";
        alreadyDispatched = builtins.elem dispatchKey ((state.dispatchedPolicies or (_: [ ])) null);
        globalPolicies = den.policies or { };
        schemaPolicies = (den.schema.${entityKind} or { }).policies or { };
        allDirectPolicies = globalPolicies // schemaPolicies;
        aspectPolicies = builtins.foldl' (acc: v: acc // v) { } (
          builtins.attrValues ((state.scopedAspectPolicies or (_: { })) null)
        );
        resolveCtx = currentCtx // {
          __entityKind = entityKind;
        };
      in
      if alreadyDispatched then
        fx.pure [ ]
      else
        fx.bind
          (fx.effects.state.modify (
            st:
            st
            // {
              dispatchedPolicies = _: ((st.dispatchedPolicies or (_: [ ])) null) ++ [ dispatchKey ];
            }
          ))
          (
            _:
            iterate allDirectPolicies aspectPolicies entityKind scope currentCtx 0 { } emptyAcc [ ] resolveCtx
          )
    );

in
{
  inherit installPolicies;
}
