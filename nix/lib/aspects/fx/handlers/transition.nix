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
  inherit (den.lib.policyTypes) policyFnArgs;

  # Schema entity kinds — used to derive targetKey from aspect-policy resolve bindings.
  schemaKinds = builtins.filter (
    n: n != "conf" && !(lib.hasPrefix "_" n) && (den.schema.${n}.isEntity or false)
  ) (builtins.attrNames (den.schema or { }));

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
      scopeHandlers = constantHandler scopedCtx;
      tagged = targetAspect // {
        __scopeHandlers = scopeHandlers;
        __ctxId = ctxId;
      };
    in
    fx.bind (aspectToEffect tagged) (
      childResult:
      # Drain deferred includes now satisfiable with the new context.
      # Note: drained includes go through aspectToEffect which re-checks
      # constraints via check-constraint. Constraints registered AFTER the
      # original deferral will apply — this is intentional (constraints are global).
      fx.bind (fx.send "drain-deferred" scopedCtx) (
        satisfiable:
        builtins.foldl' (
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
        ) (fx.pure (results ++ [ childResult ])) satisfiable
      )
    );

  # Core pipeline effects that policy handlers must not shadow.
  # Per-policy effects use "policy:<name>" prefix and are dispatched
  # by the transition handler — they are NOT in this list.
  coreEffects = [
    "into-transition"
    "ctx-seen"
    "resolve-complete"
    "emit-class"
    "emit-include"
    "emit-forward"
    "chain-push"
    "chain-pop"
    "check-constraint"
    "register-constraint"
    "register-aspect-policy"
    "dispatch-policy-includes"
    "defer-include"
    "drain-deferred"
    "get-path-set"
    "has-handler"
    "provide-to"
    "resolve-entity"
  ];

  collectPolicyHandlers =
    sourceStage: targetKey:
    let
      policies = den.policies or { };
      # Only old-style policies have from/to/handlers fields.
      # New-style policies (functions or __functor attrsets) are skipped.
      oldStyle = builtins.filter (
        p: builtins.isAttrs p && !builtins.isFunction p && !(p ? __functor) && p ? from
      ) (builtins.attrValues policies);
      matching = lib.filter (p: p.from == sourceStage && p.to == targetKey) oldStyle;
      allHandlers = builtins.foldl' (acc: p: acc // (p.handlers or { })) { } matching;
    in
    builtins.removeAttrs allHandlers coreEffects;

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
      tagged = effectiveTarget // {
        __scopeHandlers = scopeHandlers;
        __ctxId = ctxNames;
      };
      sub = den.lib.aspects.fx.pipeline.runSubPipeline {
        class = targetClass;
        self = tagged;
        ctx = scopedCtx;
        # Propagate aspect-included policies so policyFns from
        # parent pipeline fire in isolated fan-out sub-pipelines.
        extraState = {
          inherit aspectPolicies;
        };
      };
      subImports = sub.imports;
      # state.modify reads st.imports at the modify call site. This is safe
      # because fxFullResolve above is a separate pipeline whose results are
      # fully materialized before the modify runs. No concurrent handlers
      # can append to imports between construction and handling.
      mergeImports = fx.effects.state.modify (st: st // { imports = x: (st.imports x) ++ subImports; });
    in
    fx.bind mergeImports (_: fx.pure innerResults);

  # Routing decision: sibling targets (policy.from == policy.to) route
  # through provide-to for cross-entity distribution. Child targets
  # resolve locally. Manual into transitions always resolve locally.
  isSiblingRoute =
    transition: transition ? routing && transition.routing.from == transition.routing.to;

  resolveSiblingTransition =
    targetClass: sourceAspect: currentCtx: results: transition:
    builtins.foldl' (
      acc: indexed:
      fx.bind acc (
        innerResults:
        let
          newCtx = indexed.ctx;
          scopedCtx = currentCtx // newCtx;
          rawTarget = newCtx.${transition.routing.targetKey} or newCtx;
          targetEntity =
            if builtins.isAttrs rawTarget && !(rawTarget ? name) then
              builtins.trace "den: sibling route target has no name — groupByTarget will use label as key" rawTarget
            else
              rawTarget;
          # Run sub-pipeline per peer to collect traits from source entity.
          stageAspect = den.lib.resolveEntity transition.routing.from scopedCtx;
          sub = den.lib.aspects.fx.pipeline.runSubPipeline {
            class = targetClass;
            self = stageAspect;
            ctx = scopedCtx;
          };
          traits = sub.traits;
        in
        fx.send "provide-to" {
          inherit targetEntity traits;
        }
      )
    ) (fx.pure results) (lib.imap0 (i: ctx: { inherit i ctx; }) transition.contexts);

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
    if isSiblingRoute transition then
      resolveSiblingTransition targetClass sourceAspect currentCtx results transition
    else if transition.contexts == [ ] then
      # Include/exclude-only transition — no resolve targets.
      processIncludeOnly currentCtx results transition
    else
      let
        key = "${targetClass}/${lib.concatStringsSep "/" transition.path}";
        targetKey = lib.concatStringsSep "." transition.path;
        sourceProvides = sourceAspect.provides or { };
        crossProvider = sourceProvides.${targetKey} or null;
        emitCross = emitCrossProvider { inherit crossProvider sourceAspect targetKey; };
        policyHandlers = collectPolicyHandlers (sourceAspect.name or "") targetKey;
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
                  updateCtx = fx.effects.state.modify (st: st // { currentCtx = _: scopedCtx; });
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
                  # Install policy handlers for aspects resolved under this transition.
                  # Fan-out sub-pipelines (fxFullResolve) create fresh handler scopes,
                  # so policy handlers don't propagate into them. Nested transitions
                  # that install handlers for the same effect name use innermost-wins
                  # semantics (standard scope.provide shadowing).
                  withTarget =
                    if policyHandlers != { } then
                      fx.effects.scope.provide policyHandlers baseComputation
                    else
                      baseComputation;
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
                        _: fx.bind withTarget (targetResults: emitCross scopedCtx scopeHandlers ctxNames targetResults)
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
        rootCtx = (state.currentCtx or (_: { })) null;
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

        # Per-policy effects: send each matching policy effect, collect targets.
        policyEffects = den.lib.aspects.fx.handlers.policyEffectNamesFor sourceEntityKind;

        dispatchPolicies = builtins.foldl' (
          acc: effectName:
          fx.bind acc (
            prevTransitions:
            fx.bind
              (fx.send effectName {
                ctx = currentCtx;
                entityKind = sourceEntityKind;
              })
              (
                result:
                if result == null then
                  fx.pure prevTransitions
                else
                  let
                    targetPath = lib.splitString "." result.routing.targetKey;
                  in
                  fx.pure (
                    prevTransitions
                    ++ [
                      {
                        path = targetPath;
                        contexts = result.targets;
                        routing = result.routing;
                      }
                    ]
                  )
              )
          )
        ) (fx.pure manualTransitions) policyEffects;

        # Dispatch aspect-included policies from state.aspectPolicies.
        # Processes resolve effects as transitions. Include/exclude effects
        # travel WITH the transition when resolves exist (so they're injected
        # into the child entity's resolution). Include-only policyFns are
        # handled during tree-walk by dispatch-policy-includes (in aspect.nix).
        dispatchAspectPolicies =
          prevTransitions:
          let
            aspectPolicies = (state.aspectPolicies or (_: { })) null;
            traits = (state.traits or (_: { })) null;
            resolveCtx = traits // currentCtx;
            entries = lib.attrsToList aspectPolicies;
            matching = builtins.filter (
              e:
              let
                fargs = policyFnArgs e.value.fn;
                requiredArgs = builtins.filter (k: !fargs.${k}) (builtins.attrNames fargs);
                traitNames = den.traits or { };
              in
              builtins.all (k: resolveCtx ? ${k} || traitNames ? ${k}) requiredArgs
            ) entries;
          in
          builtins.foldl' (
            acc: entry:
            fx.bind acc (
              transitions:
              let
                rawEffects =
                  let
                    result = entry.value.fn resolveCtx;
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
                firstResolveKeys =
                  if resolveEffects != [ ] then builtins.attrNames (builtins.head resolveEffects).value else [ ];
                targetKey = lib.findFirst (k: builtins.elem k schemaKinds) (
                  if firstResolveKeys != [ ] then builtins.head firstResolveKeys else sourceEntityKind
                ) firstResolveKeys;
                targets = map (e: e.value) resolveEffects;
                includeAspects = map (e: e.value) includeEffects;
                excludeAspects = map (e: e.value) excludeEffects;
              in
              # Only create transitions for policyFns with resolve effects.
              # Include-only policyFns are handled by dispatch-policy-includes.
              if resolveEffects == [ ] then
                fx.pure transitions
              else
                fx.pure (
                  transitions
                  ++ [
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
                          if resolveEffects != [ ] then !((builtins.head resolveEffects).__shared or false) else true;
                      };
                    }
                  ]
                )
            )
          ) (fx.pure prevTransitions) matching;
      in
      if depth >= maxTransitionDepth then
        throw "den: transition depth exceeded ${toString maxTransitionDepth} — likely a cycle in den.policies (${sourceAspect.name or "?"})"
      else
        {
          resume = fx.bind (fx.bind dispatchPolicies dispatchAspectPolicies) (
            rawTransitions:
            let
              # Merge transitions targeting the same path — multiple policies
              # may produce separate contexts for the same target stage.
              # Concatenating contexts restores the fan-out behavior that
              # separate policy dispatch provides naturally.
              # Routing metadata is kept from the first transition per path —
              # same-path policies must have consistent from/to pairs.
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
            in
            builtins.foldl' (
              acc: transition:
              fx.bind acc (
                results:
                resolveTransition targetClass sourceAspect currentCtx (state.aspectPolicies or (_: { })
                ) results transition
              )
            ) (fx.pure [ ]) allTransitions
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
