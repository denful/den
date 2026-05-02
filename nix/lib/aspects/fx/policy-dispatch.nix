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

  # Collect non-cross-provider include effects, tagged with source policy name.
  collectIncludeEffects =
    paired:
    builtins.concatMap (
      r:
      if r.isCrossProvider then
        [ ]
      else
        map (e: e // { __sourcePolicyName = r.policyName; }) r.includeEffects
    ) paired;

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
  # Tags each include with its source policy name for unique identity
  # (prevents emit-class LOC dedup from collapsing distinct policy outputs).
  policyEmitIncludes =
    effects:
    builtins.foldl' (
      acc: e:
      fx.bind acc (
        prev:
        let
          policyName = e.__sourcePolicyName or null;
          child =
            if policyName != null && builtins.isAttrs e.value && !(e.value ? name) then
              e.value // { name = "<policy:${policyName}>"; }
            else
              e.value;
        in
        fx.bind (fx.send "emit-include" {
          inherit child;
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
              acc: e:
              fx.bind acc (
                _: fx.send "register-provide" (e.value // { __providePolicyName = e.__providePolicyName or null; })
              )
            ) (fx.pure null) provideEffects
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
    entityKind: enrichedCtx: includeAspects: isFanOut: prevResults: schemaEffect:
    let
      targetKind = resolveTargetKind entityKind schemaEffect;
      resolveBindings = schemaEffect.schema.value;
      scopedCtx = enrichedCtx // resolveBindings;
      ctxNames = mkCtxId scopedCtx;
      ctxKey = if isFanOut then "${targetKind}/{${ctxNames}}" else targetKind;
      entityClass = resolveEntityClass targetKind resolveBindings;
      scopeHandlersForCtx = constantHandler (
        scopedCtx // lib.optionalAttrs (entityClass != null) { class = entityClass; }
      );
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
          fx.send "resolve-schema-entity" {
            inherit
              targetKind
              scopedCtx
              entityClass
              includeAspects
              policyIncludes
              resolveIncludes
              ctxNames
              prevResults
              ;
          }
        else if newAspectValues != [ ] then
          mkSupplementalResolution scopeHandlersForCtx ctxNames prevResults newAspectValues
        else
          fx.pure prevResults
      );

  # Post-resolve pass: re-dispatch aspect policies registered by later siblings
  # into earlier sibling scopes. Fixes ordering-dependent policy visibility.
  #
  # Key insight: firedPolicyNames is keyed by "${targetKind}@${scopeId}" where
  # targetKind is the CHILD entity kind (e.g., "user"), not the parent entity kind
  # (e.g., "host") that processSchemaResolves receives. Each sibling's targetKind
  # from siblingMetas must be used for correct dispatchKey lookup.
  lateDispatchPass =
    _entityKind: siblingMetas:
    fx.bind (fx.effects.state.modify (st: st // { inLateDispatch = true; })) (
      _:
      fx.bind fx.effects.state.get (
        state:
        let
          allAspectPolicies = builtins.foldl' (acc: v: acc // v) { } (
            builtins.attrValues ((state.scopedAspectPolicies or (_: { })) null)
          );
          firedPerScope = (state.firedPolicyNames or (_: { })) null;
          parentScope = state.currentScope;
        in
        builtins.foldl' (
          acc: sib:
          fx.bind acc (
            _:
            let
              # Use the sibling's own target entity kind for dispatchKey — this matches
              # what iterate records when installPolicies fires at the child scope.
              dispatchKey = "${sib.targetKind}@${sib.scopeId}";
              alreadyFired = firedPerScope.${dispatchKey} or [ ];
              # Only dispatch policies NOT already fired at this scope.
              latePolicies = lib.filterAttrs (name: _: !builtins.elem name alreadyFired) allAspectPolicies;
              resolveCtx = sib.scopedCtx // {
                __entityKind = sib.targetKind;
              };
              # Dispatch late aspect policies against this scope's context.
              lateResults = dispatchAspect latePolicies alreadyFired resolveCtx;
              classified = map classifyPolicyResult lateResults;
              paired = map tagCrossProvider classified;
              lateIncludes = collectIncludeEffects paired;
              lateSchemas = collectSchemaEffects paired;
              hasLateEffects = lateIncludes != [ ] || lateSchemas != [ ];
              scopeHandlersForCtx = constantHandler (
                sib.scopedCtx // lib.optionalAttrs (sib.entityClass != null) { class = sib.entityClass; }
              );
            in
            if latePolicies == { } || !hasLateEffects then
              fx.pure null
            else
              # Push sibling scope, provide its context, emit late includes.
              fx.bind (fx.effects.state.modify (st: st // { currentScope = sib.scopeId; })) (
                _:
                fx.bind
                  (fx.effects.scope.provide scopeHandlersForCtx (
                    fx.bind (policyEmitIncludes lateIncludes) (
                      _:
                      if lateSchemas != [ ] then
                        let
                          lateIncludeAspects = map (e: e.value) lateIncludes;
                        in
                        processSchemaResolvesInner true sib.targetKind lateIncludeAspects lateSchemas sib.scopedCtx
                      else
                        fx.pure null
                    )
                  ))
                  (
                    _:
                    # Restore parent scope.
                    fx.effects.state.modify (st: st // { currentScope = parentScope; })
                  )
              )
          )
        ) (fx.pure null) siblingMetas
      )
    );

  # Process schema resolve effects: ctx-seen dedup, push scope, walk entity, pop scope.
  # When processing fan-out (multiple siblings), runs a late-dispatch pass after
  # all resolves to fix cross-sibling aspect policy visibility.
  processSchemaResolves =
    entityKind: includeAspects: schemaEffects: enrichedCtx:
    processSchemaResolvesInner false entityKind includeAspects schemaEffects enrichedCtx;

  processSchemaResolvesInner =
    isLatePass: entityKind: includeAspects: schemaEffects: enrichedCtx:
    let
      isFanOut = builtins.length schemaEffects > 1;
      mainFold = builtins.foldl' (
        acc: schemaEffect:
        fx.bind acc (
          prevResults:
          processSingleResolve entityKind enrichedCtx includeAspects isFanOut prevResults schemaEffect
        )
      ) (fx.pure [ ]) schemaEffects;
    in
    if !isFanOut || isLatePass then
      mainFold
    else
      fx.bind fx.effects.state.get (
        preState:
        # Skip late dispatch if already inside a late-dispatch pass (state flag).
        if (preState.inLateDispatch or false) then
          mainFold
        else
          fx.bind mainFold (
            allResults:
            let
              # Compute sibling metadata purely from schema effects.
              siblingMetas = map (
                schemaEffect:
                let
                  targetKind = resolveTargetKind entityKind schemaEffect;
                  resolveBindings = schemaEffect.schema.value;
                  scopedCtx = enrichedCtx // resolveBindings;
                  entityClass = resolveEntityClass targetKind resolveBindings;
                in
                {
                  inherit targetKind scopedCtx entityClass;
                  scopeId = mkScopeId scopedCtx;
                }
              ) schemaEffects;
            in
            fx.bind (lateDispatchPass entityKind siblingMetas) (_: fx.pure allResults)
          )
      );

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
    entityKind: currentCtx: accEnrichment: dispatched: combinedEffects:
    let
      enrichedCtx = currentCtx // accEnrichment // dispatched.enrichment;
      includeAspects = map (e: e.value) combinedEffects.includeEffects;
      hasSchemaResolves = combinedEffects.schemaEffects != [ ];
    in
    fx.bind (policyEmitExcludes combinedEffects.excludeEffects) (
      _:
      fx.bind
        (policyEmitEffects (combinedEffects.routeEffects) (combinedEffects.instantiateEffects) (
          combinedEffects.provideEffects
        ))
        (
          _:
          if hasSchemaResolves then
            processSchemaResolves entityKind includeAspects combinedEffects.schemaEffects enrichedCtx
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
    allDirectPolicies: aspectPolicies: entityKind: currentCtx: iteration: accEnrichment: accEffects: firedPolicies: currentResolveCtx:
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
      # Record fired policy names for late-dispatch pass (cross-sibling visibility).
      fx.bind (fx.effects.state.modify (
        st:
        let
          dispatchKey = "${entityKind}@${st.currentScope}";
        in
        st
        // {
          firedPolicyNames =
            _:
            let
              all = (st.firedPolicyNames or (_: { })) null;
            in
            all // { ${dispatchKey} = updatedFired; };
        }
      )) (_: emitFinalEffects entityKind currentCtx accEnrichment dispatched combinedEffects)
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
            iterate allDirectPolicies aspectPolicies entityKind currentCtx (
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
        # Merge handler-derived ctx (from aspect's __scopeHandlers) with
        # scopeContexts. Handler ctx takes precedence — it reflects the
        # actual scope.provide context for entities resolved inline
        # (without their own setScope).
        scopeCtx = if scope == null then { } else (state.scopeContexts null).${scope} or { };
        currentCtx = scopeCtx // ctx;
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
        fx.bind (fx.effects.state.modify (
          st:
          st
          // {
            dispatchedPolicies = _: ((st.dispatchedPolicies or (_: [ ])) null) ++ [ dispatchKey ];
          }
        )) (_: iterate allDirectPolicies aspectPolicies entityKind currentCtx 0 { } emptyAcc [ ] resolveCtx)
    );

in
{
  inherit installPolicies;
}
