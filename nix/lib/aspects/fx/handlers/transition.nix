{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  inherit (den.lib.aspects.fx.aspect) aspectToEffect;
  inherit (den.lib.aspects.fx.handlers) constantHandler;
  inherit (den.lib.aspects) isParametricWrapper;
  inherit (den.lib.aspects.fx.identity) pathKey aspectPath;
  inherit (den.lib.aspects.fx.pipeline) mkScopeId;
  inherit (den.lib.policyTypes) policyFnArgs;
  inherit (den.lib.synthesizePolicies) resolveArgsSatisfied;

  # Schema entity kinds — used to derive targetKey from aspect-policy resolve bindings.
  schemaKinds = builtins.filter (
    n: n != "conf" && !(lib.hasPrefix "_" n) && (den.schema.${n}.isEntity or false)
  ) (builtins.attrNames (den.schema or { }));

  # Classify a resolve effect into schema transition vs enrichment.
  # Schema keys create child entities; non-schema keys enrich the current context.
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

  maxEnrichmentIterations = 10;

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

  flattenInto =
    attrset: prefix:
    lib.concatLists (
      lib.mapAttrsToList (
        name: v:
        let
          path = prefix ++ [ name ];
        in
        if builtins.isList v then
          [
            {
              inherit path;
              contexts = v;
            }
          ]
        else
          flattenInto v path
      ) attrset
    );

  # Resolve a single context value by tagging the target aspect with
  # __scopeHandlers and resolving it. For fan-out transitions, each context value's target
  # gets its own inner resolution with independent dedup state.
  resolveContextValue =
    parentCtx: targetAspect: results: newCtx:
    let
      scopedCtx = parentCtx // newCtx;
      # ctxId from merged context — new bindings alone may not be unique
      # across different parent contexts (e.g., user "alice" on host A vs B).
      ctxId = mkCtxId scopedCtx;
      newScopeId = mkScopeId scopedCtx;
      scopeHandlers = constantHandler scopedCtx;
      tagged = targetAspect // {
        __scopeHandlers = scopeHandlers;
        __ctxId = ctxId;
      };
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
      fx.bind (aspectToEffect tagged) (
        childResult:
        # Drain deferred includes now satisfiable with the new context.
        # Note: drained includes go through aspectToEffect which re-checks
        # constraints via check-constraint. Constraints registered AFTER the
        # original deferral will apply — this is intentional (constraints are global).
        fx.bind (fx.send "drain-deferred" scopedCtx) (
          satisfiable:
          fx.bind (fx.send "drain-dead-letters" null) (
            _:
            fx.bind
              (builtins.foldl' (
                acc: deferred:
                fx.bind acc (
                  prevResults:
                  let
                    deferredTagged = deferred.child // {
                      __scopeHandlers = scopeHandlers;
                      __ctxId = ctxId;
                    };
                  in
                  fx.bind (aspectToEffect deferredTagged) (resolved: fx.pure (prevResults ++ [ resolved ]))
                )
              ) (fx.pure (results ++ [ childResult ])) satisfiable)
              (allResults: fx.bind popScope (_: fx.pure allResults))
          )
        )
      )
    );

  emitCrossProvider =
    {
      crossProvider,
      sourceAspect,
      targetKey,
    }:
    scopedCtx: scopeHandlers: ctxId: prevResults:
    if crossProvider == null then
      fx.pure prevResults
    else
      let
        wrapped =
          if isParametricWrapper crossProvider && crossProvider.__args != { } then
            crossProvider
            // {
              __scopeHandlers = scopeHandlers;
              __ctxId = ctxId;
            }
          else
            let
              rawFn = if isParametricWrapper crossProvider then crossProvider.__fn else crossProvider;
              crossProviderArgs = lib.functionArgs rawFn;
              crossCtx =
                if crossProviderArgs != { } then builtins.intersectAttrs crossProviderArgs scopedCtx else scopedCtx;
              crossResult = rawFn crossCtx;
            in
            if lib.isFunction crossResult && !builtins.isAttrs crossResult then
              {
                name = "${sourceAspect.name or "?"}.provides.${targetKey}";
                meta = crossProvider.meta or { };
                __fn = crossResult;
                __args = lib.functionArgs crossResult;
                __scopeHandlers = scopeHandlers;
                __ctxId = ctxId;
              }
            else
              crossResult
              // {
                __scopeHandlers = scopeHandlers;
                __ctxId = ctxId;
              };
      in
      fx.bind (aspectToEffect wrapped) (crossResolved: fx.pure (prevResults ++ [ crossResolved ]));

  resolveFanOut =
    {
      targetClass,
      effectiveTarget,
      scopedCtx,
      scopeHandlers,
      ctxNames,
      aspectPolicies ? (_: { }),
    }:
    innerResults:
    let
      newScopeId = mkScopeId scopedCtx;
      tagged = effectiveTarget // {
        __scopeHandlers = scopeHandlers;
        __ctxId = ctxNames;
      };
      # Inline sub-pipeline: isolated resolution with fresh state.
      # Replaces the old runSubPipeline call — each fan-out entity
      # gets its own pipeline with forward application.
      subResult = den.lib.aspects.fx.pipeline.fxFullResolve {
        class = targetClass;
        self = tagged;
        ctx = scopedCtx;
        extraState = {
          inherit aspectPolicies;
        };
      };
      subRootScope = mkScopeId scopedCtx;
      subFinalCtx = (subResult.state.scopeContexts null).${subRootScope} or scopedCtx;
      subScopedClassImportsRaw = subResult.state.scopedClassImports null;
      subRawClassImports =
        let
          subWrappedPerScope = lib.mapAttrs (
            scopeId: scopeClasses:
            let
              scopeCtx = (subResult.state.scopeContexts null).${scopeId} or scopedCtx;
            in
            den.lib.aspects.fx.pipeline.wrapCollectedClasses scopeCtx scopeClasses
          ) subScopedClassImportsRaw;
        in
        builtins.foldl' (
          acc: scopeData:
          lib.zipAttrsWith (_: builtins.concatLists) [
            acc
            scopeData
          ]
        ) { } (builtins.attrValues subWrappedPerScope);
      subForwardSpecs = lib.concatLists (lib.attrValues (subResult.state.scopedForwardSpecs null));
      subWrapped = subRawClassImports;
      subForwarded = den.lib.aspects.fx.pipeline.applyForwardSpecs {
        forwardSpecs = subForwardSpecs;
        classImports = subWrapped;
        traitModule = null;
        hasTraitSchemas = false;
      };
      subClassImports = subForwarded.classImports;
      # Push scope, merge sub-pipeline results, pop scope.
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
      # Merge sub-pipeline results into parent state: flat classImports
      # plus all scoped state fields. Scope IDs are globally unique
      # (mkScopeId on entity context), so simple // merge is safe for
      # most fields. scopedClassImports uses mergeScoped to handle the
      # unlikely case of overlapping scope+class entries.
      subScopedCI = subResult.state.scopedClassImports null;
      subScopedTraits = subResult.state.scopedTraits null;
      subScopedDT = subResult.state.scopedDeferredTraits null;
      subScopedFS = subResult.state.scopedForwardSpecs null;
      subScopedDLQ = subResult.state.scopedDeadLetterQueue null;
      subScopedInstantiates = subResult.state.scopedInstantiates null;
      subScopeContexts = subResult.state.scopeContexts null;
      subScopeParent = subResult.state.scopeParent null;
      subScopeChildren = subResult.state.scopeChildren null;
      # Merge helper: combine two attrsets where values are lists or attrsets-of-lists.
      mergeScoped =
        parent: sub:
        parent
        // lib.mapAttrs (
          k: v:
          if parent ? ${k} then
            if builtins.isList v then
              parent.${k} ++ v
            else if builtins.isAttrs v then
              lib.zipAttrsWith (_: builtins.concatLists) [
                parent.${k}
                v
              ]
            else
              v
          else
            v
        ) sub;
      mergeImports = fx.effects.state.modify (
        st:
        st
        // {
          classImports =
            x:
            let
              current = st.classImports x;
            in
            lib.zipAttrsWith (_: builtins.concatLists) [
              current
              subClassImports
            ];
          scopedClassImports = _: mergeScoped (st.scopedClassImports null) subScopedCI;
          scopedTraits = _: (st.scopedTraits null) // subScopedTraits;
          scopedDeferredTraits = _: (st.scopedDeferredTraits null) // subScopedDT;
          scopedForwardSpecs = _: (st.scopedForwardSpecs null) // subScopedFS;
          scopedDeadLetterQueue = _: (st.scopedDeadLetterQueue null) // subScopedDLQ;
          scopedInstantiates = _: (st.scopedInstantiates null) // subScopedInstantiates;
          scopeContexts = _: (st.scopeContexts null) // subScopeContexts;
          scopeParent = _: (st.scopeParent null) // subScopeParent;
          scopeChildren = _: (st.scopeChildren null) // subScopeChildren;
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
    fx.bind pushScope (_: fx.bind mergeImports (_: fx.bind popScope (_: fx.pure innerResults)));

  # Register exclude constraints from policy routing before resolution.
  registerExcludes =
    policyName: excludes:
    if excludes == [ ] then
      fx.pure null
    else
      builtins.foldl' (
        acc: aspectRef:
        fx.bind acc (
          _:
          fx.send "register-constraint" {
            type = "exclude";
            scope = "subtree";
            identity = pathKey (aspectPath aspectRef);
            owner = policyName;
          }
        )
      ) (fx.pure null) excludes;

  # Process include-only transitions (no resolve targets) by emitting
  # includes and registering excludes in the current context.
  processIncludeOnly =
    currentCtx: results: transition:
    let
      routing = transition.routing or { };
      aspects = routing.aspects or [ ];
      excludes = routing.excludes or [ ];
      scopeHandlers = constantHandler currentCtx;
      ctxNames = mkCtxId currentCtx;
    in
    fx.bind (registerExcludes (routing.policyName or "policy") excludes) (
      _:
      builtins.foldl' (
        acc: aspect:
        fx.bind acc (
          prevResults:
          fx.bind (fx.send "emit-include" {
            child = aspect;
            idx = null;
            __parentScopeHandlers = scopeHandlers;
            __parentCtxId = ctxNames;
          }) (_: fx.pure prevResults)
        )
      ) (fx.pure results) aspects
    );

  resolveTransition =
    targetClass: sourceAspect: currentCtx: aspectPolicies: results: transition:
    if transition.contexts == [ ] then
      # Include/exclude-only transition — no resolve targets.
      processIncludeOnly currentCtx results transition
    else if transition ? routing && transition.routing.from == transition.routing.to then
      # Sibling route (from == to): skip. Previously routed through provide-to
      # for cross-entity trait distribution; scope inheritance replaces this.
      fx.pure results
    else
      let
        key = "${targetClass}/${lib.concatStringsSep "/" transition.path}";
        targetKey = lib.concatStringsSep "." transition.path;
        sourceProvides = sourceAspect.provides or { };
        crossProvider = sourceProvides.${targetKey} or null;
        emitCross = emitCrossProvider { inherit crossProvider sourceAspect targetKey; };
        excludes = (transition.routing or { }).excludes or [ ];
      in
      # Register exclude constraints before resolving targets.
      fx.bind (registerExcludes ((transition.routing or { }).policyName or "policy") excludes) (
        _:
        fx.bind
          (fx.send "resolve-entity" {
            kind = lib.concatStringsSep "." transition.path;
          })
          (
            rawTarget:
            let
              # Inject policy-declared aspects into the target's includes.
              policyAspects = (transition.routing or { }).aspects or [ ];
              effectiveTarget = rawTarget // {
                includes = (rawTarget.includes or [ ]) ++ policyAspects;
              };
            in
            let
              isFanOut = builtins.length transition.contexts > 1;
              # Pre-index contexts so fan-out dedup keys are unique even when
              # policy-contributed contexts have identical attr names
              # (e.g., {fromClass=_:"packages"} vs {fromClass=_:"files"}).
              indexedContexts = lib.imap0 (i: ctx: {
                inherit i;
                ctx = ctx;
              }) transition.contexts;
            in
            builtins.foldl' (
              acc: indexed:
              fx.bind acc (
                innerResults:
                let
                  newCtx = indexed.ctx;
                  scopedCtx = currentCtx // newCtx;
                  # Use merged context for dedup — new bindings alone may not
                  # be unique across parent contexts.
                  ctxNames = mkCtxId scopedCtx;
                  ctxKey = if isFanOut then "${key}/{${ctxNames}}" else key;
                  scopeHandlers = constantHandler scopedCtx;
                  updateCtx = fx.effects.state.modify (
                    st:
                    st
                    // {
                      scopeContexts = _: (st.scopeContexts null) // { ${st.currentScope} = scopedCtx; };
                    }
                  );
                  baseComputation =
                    if isFanOut && ((transition.routing or { }).isolateFanOut or false) then
                      resolveFanOut {
                        inherit
                          targetClass
                          effectiveTarget
                          scopedCtx
                          scopeHandlers
                          ctxNames
                          ;
                        inherit aspectPolicies;
                      } innerResults
                    else
                      resolveContextValue currentCtx effectiveTarget innerResults newCtx;
                in
                fx.bind
                  (fx.send "ctx-seen" {
                    key = ctxKey;
                    aspects = map (a: pathKey (aspectPath a)) policyAspects;
                    aspectValues = policyAspects;
                  })
                  (
                    { isFirst, newAspectValues }:
                    if isFirst then
                      fx.bind updateCtx (
                        _: fx.bind baseComputation (targetResults: emitCross scopedCtx scopeHandlers ctxNames targetResults)
                      )
                    else if newAspectValues != [ ] then
                      # Supplemental aspects for an already-resolved entity:
                      # emit each new aspect as an include with parent scope
                      # so parametric aspects can resolve their args.
                      builtins.foldl' (
                        acc: aspect:
                        fx.bind acc (
                          prevResults:
                          fx.bind (fx.send "emit-include" {
                            child = aspect;
                            idx = null;
                            __parentScopeHandlers = scopeHandlers;
                            __parentCtxId = ctxNames;
                          }) (_: fx.pure prevResults)
                        )
                      ) (fx.pure innerResults) newAspectValues
                    else
                      fx.pure innerResults
                  )
              )
            ) (fx.pure results) indexedContexts
          )
      );

  maxTransitionDepth = 50;

  transitionHandler = {
    "into-transition" =
      { param, state }:
      let
        sourceAspect = param.self;
        scope = state.currentScope;
        rootCtx = if scope == null then { } else (state.scopeContexts null).${scope} or { };
        # Merge the source aspect's context so that stages resolved with
        # explicit context have their context available for the into function.
        aspectCtx = den.lib.aspects.fx.aspect.ctxFromHandlers (sourceAspect.__scopeHandlers or { });
        currentCtx = rootCtx // aspectCtx;
        depth = state.transitionDepth or 0;
        targetClass = state.class or "nixos";
        sourceEntityKind = sourceAspect.name or "";

        # Manual into transitions (from entity kind definition).
        manualIntoFn = param.intoFn;
        manualTransitions = if manualIntoFn != null then flattenInto (manualIntoFn currentCtx) [ ] else [ ];

        # Direct policy dispatch: iterate den.policies, check scope + args, call directly.
        traits = (state.traits or (_: { })) null;
        resolveCtx = traits // currentCtx // { __entityKind = sourceEntityKind; };
        # Schema-scoped policies: only fire for matching entity kind.
        schemaPolicies = (den.schema.${sourceEntityKind} or { }).policies or { };
        allPolicies = (den.policies or { }) // schemaPolicies;

        # Dispatch all policies (global + aspect) against a given context,
        # classifying resolve effects into schema transitions vs enrichment.
        # Returns { transitions, enrichment } where enrichment is an attrset
        # of non-schema key bindings to install into the current context.
        mkDispatch =
          resolveCtx':
          let
            # --- Global policies ---
            globalResults = lib.concatLists (
              lib.mapAttrsToList (
                name: policy:
                let
                  argsOk = resolveArgsSatisfied policy resolveCtx';
                in
                if !argsOk then
                  [ ]
                else
                  let
                    rawEffects =
                      let
                        result = policy resolveCtx';
                      in
                      if builtins.isList result then result else [ result ];
                    resolveEffects = builtins.filter (
                      e: builtins.isAttrs e && (e.__policyEffect or "") == "resolve" && e.value != { }
                    ) rawEffects;
                    includeEffects = builtins.filter (
                      e: builtins.isAttrs e && (e.__policyEffect or "") == "include"
                    ) rawEffects;
                    excludeEffects = builtins.filter (
                      e: builtins.isAttrs e && (e.__policyEffect or "") == "exclude"
                    ) rawEffects;
                    routeEffects = builtins.filter (
                      e: builtins.isAttrs e && (e.__policyEffect or "") == "route"
                    ) rawEffects;
                    instantiateEffects = builtins.filter (
                      e: builtins.isAttrs e && (e.__policyEffect or "") == "instantiate"
                    ) rawEffects;
                    includeAspects = map (e: e.value) includeEffects;
                    excludeAspects = map (e: e.value) excludeEffects;
                    isolateFanOut =
                      if schemaResolves != [ ] && ((builtins.head schemaResolves).__shared or false) then false else true;
                    # Classify each resolve effect.
                    classified = map classifyResolve resolveEffects;
                    schemaEffects = builtins.filter (c: c.schema != null) classified;
                    enrichEffects = builtins.filter (c: c.enrichment != null) classified;
                    mergedEnrichment = builtins.foldl' (acc: c: acc // c.enrichment) { } enrichEffects;
                    # Build transition from schema effects (if any).
                    schemaResolves = map (c: c.schema) schemaEffects;
                    firstSchemaEffect = if schemaResolves != [ ] then builtins.head schemaResolves else null;
                    effectTargetKind =
                      if firstSchemaEffect != null then firstSchemaEffect.__targetKind or null else null;
                    firstSchemaKeys = if schemaResolves != [ ] then builtins.attrNames firstSchemaEffect.value else [ ];
                    targetKey =
                      if effectTargetKind != null then
                        effectTargetKind
                      else
                        lib.findFirst (k: builtins.elem k schemaKinds) (
                          if firstSchemaKeys != [ ] then builtins.head firstSchemaKeys else sourceEntityKind
                        ) firstSchemaKeys;
                    targets = map (e: e.value) schemaResolves;
                    # Include/exclude-only policies (no resolve effects) still
                    # need a transition with empty contexts so processIncludeOnly
                    # can register their aspects and excludes.
                    hasRouting = includeAspects != [ ] || excludeAspects != [ ];
                    transition =
                      if schemaResolves == [ ] && !hasRouting then
                        [ ]
                      else
                        [
                          {
                            path = lib.splitString "." targetKey;
                            contexts = targets;
                            routing = {
                              from = sourceEntityKind;
                              to = targetKey;
                              inherit targetKey;
                              policyName = name;
                              aspects = includeAspects;
                              excludes = excludeAspects;
                              inherit isolateFanOut;
                            };
                          }
                        ];
                  in
                  if rawEffects == [ ] then
                    [ ]
                  else
                    [
                      {
                        inherit
                          transition
                          mergedEnrichment
                          routeEffects
                          instantiateEffects
                          ;
                        policyName = name;
                      }
                    ]
              ) allPolicies
            );

            # --- Aspect policies ---
            aspectPoliciesVal = (state.aspectPolicies or (_: { })) null;
            aspectEntries = lib.attrsToList aspectPoliciesVal;
            aspectTraitNames = den.traits or { };
            matchingAspect = builtins.filter (
              e:
              let
                fargs = policyFnArgs e.value.fn;
                requiredArgs = builtins.filter (k: !fargs.${k}) (builtins.attrNames fargs);
              in
              builtins.all (k: resolveCtx' ? ${k} || aspectTraitNames ? ${k}) requiredArgs
            ) aspectEntries;
            aspectResults = map (
              entry:
              let
                rawEffects =
                  let
                    result = entry.value.fn resolveCtx';
                  in
                  if builtins.isList result then result else [ result ];
                resolveEffects = builtins.filter (
                  e: builtins.isAttrs e && (e.__policyEffect or "") == "resolve" && e.value != { }
                ) rawEffects;
                includeEffects = builtins.filter (
                  e: builtins.isAttrs e && (e.__policyEffect or "") == "include"
                ) rawEffects;
                excludeEffects = builtins.filter (
                  e: builtins.isAttrs e && (e.__policyEffect or "") == "exclude"
                ) rawEffects;
                routeEffects = builtins.filter (
                  e: builtins.isAttrs e && (e.__policyEffect or "") == "route"
                ) rawEffects;
                instantiateEffects = builtins.filter (
                  e: builtins.isAttrs e && (e.__policyEffect or "") == "instantiate"
                ) rawEffects;
                includeAspects = map (e: e.value) includeEffects;
                excludeAspects = map (e: e.value) excludeEffects;
                classified = map classifyResolve resolveEffects;
                schemaEffects = builtins.filter (c: c.schema != null) classified;
                enrichEffects = builtins.filter (c: c.enrichment != null) classified;
                mergedEnrichment = builtins.foldl' (acc: c: acc // c.enrichment) { } enrichEffects;
                schemaResolves = map (c: c.schema) schemaEffects;
                firstSchemaKeys =
                  if schemaResolves != [ ] then builtins.attrNames (builtins.head schemaResolves).value else [ ];
                targetKey = lib.findFirst (k: builtins.elem k schemaKinds) (
                  if firstSchemaKeys != [ ] then builtins.head firstSchemaKeys else sourceEntityKind
                ) firstSchemaKeys;
                targets = map (e: e.value) schemaResolves;
                transition =
                  if schemaResolves == [ ] then
                    [ ]
                  else
                    [
                      {
                        path = lib.splitString "." targetKey;
                        contexts = targets;
                        routing = {
                          from = sourceEntityKind;
                          to = targetKey;
                          inherit targetKey;
                          policyName = entry.name;
                          aspects = includeAspects;
                          excludes = excludeAspects;
                          isolateFanOut =
                            if schemaResolves != [ ] then !((builtins.head schemaResolves).__shared or false) else true;
                        };
                      }
                    ];
              in
              # Only create transitions for policies with resolve effects.
              # Include-only policies are handled by dispatch-policy-includes.
              if resolveEffects == [ ] then
                {
                  transition = [ ];
                  inherit mergedEnrichment routeEffects instantiateEffects;
                  policyName = entry.name;
                }
              else
                {
                  inherit
                    transition
                    mergedEnrichment
                    routeEffects
                    instantiateEffects
                    ;
                  policyName = entry.name;
                }
            ) matchingAspect;

            # --- Combine ---
            allResults = globalResults ++ aspectResults;
            allTransitions = builtins.concatLists (map (r: r.transition) allResults);
            allEnrichment = builtins.foldl' (acc: r: acc // r.mergedEnrichment) { } allResults;
            allRouteEffects = builtins.concatMap (
              r: map (re: re // { __routePolicyName = r.policyName; }) (r.routeEffects or [ ])
            ) allResults;
            allInstantiateEffects = builtins.concatMap (
              r: map (ie: ie // { __instantiatePolicyName = r.policyName; }) (r.instantiateEffects or [ ])
            ) allResults;
          in
          {
            transitions = allTransitions;
            enrichment = allEnrichment;
            routeEffects = allRouteEffects;
            instantiateEffects = allInstantiateEffects;
          };

        # Fixed-point enrichment loop: dispatch policies, collect enrichment,
        # install enrichment into context, re-dispatch until stable.
        iterateEnrichment =
          iteration: accTransitions: accEnrichment: accRouteEffects: accInstantiateEffects: firedPolicies: currentResolveCtx:
          let
            dispatched = mkDispatch currentResolveCtx;
            # Filter out transitions from already-fired policies.
            newTransitions = builtins.filter (
              t: !(builtins.elem ((t.routing or { }).policyName or "") firedPolicies)
            ) dispatched.transitions;
            newFired = firedPolicies ++ map (t: (t.routing or { }).policyName or "") newTransitions;
            combinedTransitions = accTransitions ++ newTransitions;
            newRouteEffects = builtins.filter (
              re: !(builtins.elem (re.__routePolicyName or "") firedPolicies)
            ) dispatched.routeEffects;
            combinedRouteEffects = accRouteEffects ++ newRouteEffects;
            newInstantiateEffects = builtins.filter (
              ie: !(builtins.elem (ie.__instantiatePolicyName or "") firedPolicies)
            ) dispatched.instantiateEffects;
            combinedInstantiateEffects = accInstantiateEffects ++ newInstantiateEffects;
            # Only enrichment keys not already accumulated count as new.
            newEnrichKeys = builtins.filter (k: !accEnrichment ? ${k}) (
              builtins.attrNames dispatched.enrichment
            );
            combinedEnrichment = accEnrichment // dispatched.enrichment;
          in
          if newEnrichKeys == [ ] then
            # Stable — no new enrichment, return accumulated results.
            fx.pure {
              transitions = combinedTransitions;
              enrichment = combinedEnrichment;
              routeEffects = combinedRouteEffects;
              instantiateEffects = combinedInstantiateEffects;
            }
          else if iteration >= maxEnrichmentIterations then
            throw "den: enrichment iteration exceeded ${toString maxEnrichmentIterations} — likely a cycle in enrichment policies (${sourceAspect.name or "?"})"
          else
            # Apply enrichment: update state, install handlers, drain deferred.
            let
              enrichedCtx = currentCtx // combinedEnrichment;
              enrichHandlers = constantHandler combinedEnrichment;
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
                fx.bind
                  (fx.effects.scope.provide enrichHandlers (
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
                              ctxId = mkCtxId enrichedCtx;
                              deferredTagged = deferred.child // {
                                __scopeHandlers = scopeHandlers;
                                __ctxId = ctxId;
                              };
                            in
                            fx.bind (aspectToEffect deferredTagged) (_: fx.pure null)
                          )
                        ) (fx.pure null) satisfiable
                      )
                    )
                  ))
                  (
                    _:
                    let
                      nextResolveCtx = traits // enrichedCtx // { __entityKind = sourceEntityKind; };
                    in
                    iterateEnrichment (iteration + 1) combinedTransitions combinedEnrichment combinedRouteEffects
                      combinedInstantiateEffects
                      newFired
                      nextResolveCtx
                  )
              );
      in
      if depth >= maxTransitionDepth then
        throw "den: transition depth exceeded ${toString maxTransitionDepth} — likely a cycle in den.policies (${sourceAspect.name or "?"})"
      else
        {
          resume = fx.bind (iterateEnrichment 0 manualTransitions { } [ ] [ ] [ ] resolveCtx) (
            result:
            let
              rawTransitions = result.transitions;
              enrichment = result.enrichment;
              effectiveCtx = currentCtx // enrichment;
              # Merge transitions targeting the same path + aspect set.
              # Different aspect sets stay separate — they represent
              # distinct resolution configurations for the same target.
              mergeByPath = builtins.foldl' (
                acc: t:
                let
                  aspectIds = map (a: pathKey (aspectPath a)) ((t.routing or { }).aspects or [ ]);
                  sortedAspects = lib.sort (a: b: a < b) aspectIds;
                  aspectsKey = builtins.concatStringsSep "," sortedAspects;
                  mergeKey = "${lib.concatStringsSep "." t.path}|${aspectsKey}";
                in
                acc
                // {
                  ${mergeKey} =
                    if acc ? ${mergeKey} then
                      acc.${mergeKey}
                      // {
                        contexts = acc.${mergeKey}.contexts ++ t.contexts;
                      }
                    else
                      t;
                }
              ) { } rawTransitions;
              allTransitions = builtins.attrValues mergeByPath;
              resolveAllTransitions = builtins.foldl' (
                acc: transition:
                fx.bind acc (
                  results:
                  resolveTransition targetClass sourceAspect effectiveCtx (state.aspectPolicies or (_: { })
                  ) results transition
                )
              ) (fx.pure [ ]) allTransitions;
              emitRoutes = builtins.foldl' (
                acc: re: fx.bind acc (_: fx.send "register-route" re.value)
              ) (fx.pure null) result.routeEffects;
              emitInstantiates = builtins.foldl' (
                acc: ie: fx.bind acc (_: fx.send "register-instantiate" ie.value)
              ) (fx.pure null) result.instantiateEffects;
            in
            fx.bind resolveAllTransitions (
              transitionResults: fx.bind emitRoutes (_: fx.bind emitInstantiates (_: fx.pure transitionResults))
            )
          );
          state = state // {
            transitionDepth = depth + 1;
          };
        };
  };

in
{
  inherit transitionHandler;
}
