# Post-pipeline phase: assemble pipe data from scopedClassImports
# and inject into scope contexts for delivery via wrapClassModule.
{
  lib,
  den,
  ...
}:
let
  pipeRegistry = den.quirks or { };
  pipeNames = builtins.attrNames pipeRegistry;

  # Extract raw quirk value from a pipe entry.
  # Pipe entries are raw emit-class params with __isPipeEntry = true.
  # The actual quirk value is in the `module` field.
  extractValue = entry: entry.module or entry;

  # Auto-flatten list-valued quirk entries.
  # If a quirk value is a list, each element becomes a separate entry.
  flattenAndExtract =
    entries:
    builtins.concatMap (
      entry:
      let
        val = extractValue entry;
      in
      if builtins.isList val then val else [ val ]
    ) entries;

  # Parent-config arg names registered by nested classes (home-manager exposes
  # the owner config as `osConfig`). A thunk reading `config` or any of these
  # binds to the evalModules fixpoint.
  parentArgNames = builtins.filter (a: a != null) (
    map (c: c.parentArg or null) (builtins.attrValues (den.classes or { }))
  );
  readsParentArg = a: builtins.any (k: a ? ${k}) parentArgNames;

  # Detect config-dependent thunks: functions taking `config` (the producer's
  # class config) and/or a registered parent-config arg (the enclosing owner
  # config). Both bind to the evalModules fixpoint, so they are deferred there.
  isConfigDependent =
    val:
    builtins.isFunction val
    && (
      let
        a = builtins.functionArgs val;
      in
      a ? config || readsParentArg a
    );

  # Pipeline-parametric values require pipeline context args (host, user, etc.)
  # but neither config nor a parent-config arg. Resolved eagerly via scope context.
  isPipelineParametric =
    val:
    builtins.isFunction val
    && (
      let
        a = builtins.functionArgs val;
      in
      !(a ? config) && !(readsParentArg a)
    );

  # Resolve a local pipeline-parametric value eagerly using scope context.
  # These are quirk values like `{ host, ... }: { addr = host.addr; }` that
  # require pipeline context (host, user, etc.) but not NixOS config.
  # Without this, the raw function would be passed to consumers as-is.
  # If required args (non-optional, not `lib`) are missing from scope context,
  # the value is passed through unresolved — the consumer is responsible for
  # providing the missing args (e.g., perSystem CRD build pipeline provides pkgs).
  resolveLocalParametric =
    scopeCtx: val:
    if isPipelineParametric val then
      let
        thunkArgs = builtins.functionArgs val;
        requiredArgs = builtins.filter (k: !(thunkArgs.${k} or false) && k != "lib") (
          builtins.attrNames thunkArgs
        );
        allSatisfied = builtins.all (k: scopeCtx ? ${k}) requiredArgs;
      in
      if !allSatisfied then
        [ val ]
      else
        let
          ctxArgs = lib.genAttrs (builtins.filter (k: scopeCtx ? ${k}) (builtins.attrNames thunkArgs)) (
            k: scopeCtx.${k}
          );
          result = val (ctxArgs // { inherit lib; });
        in
        if builtins.isList result then result else [ result ]
    else
      [ val ];

  # Mark a config-dependent value for deferred resolution inside evalModules.
  # `producer` tags the marker with the PRODUCING scope's class and name so the
  # module wrapper resolves it against the producing class + scope's config —
  # not the consuming module's. Already-marked values (re-mark on an exposed/
  # inherited path) pass through unchanged, keeping their original producer tag.
  markConfigThunk =
    producer: v:
    if isConfigDependent v then
      {
        __configThunk = true;
        __fn = v;
        __producerClass = producer.class or null;
        __producerName = producer.name or null;
      }
    else
      v;

  # Mark all config-dependent entries in a value list with their producer.
  markConfigThunks = producer: map (markConfigThunk producer);

  # Producer tag (class + name) for a scope, read from pipeline state. The class
  # selects the producer's config-resolution route via den.classes.<class>.parentPath.
  producerOf =
    scopeEntityClass: scopeContexts: sid:
    let
      ctx = scopeContexts.${sid} or { };
    in
    {
      class = scopeEntityClass.${sid} or null;
      name = ctx.user.name or ctx.home.name or null;
    };

  # The PRODUCER's `config` (class config), the enclosing config-`owner` config,
  # and the class's `parentArg` name, used to resolve cross-scope config-
  # dependent emits at their SOURCE (not the consumer). A scope that owns a
  # config directly (a hostConfigs key — e.g. a host) has config == owner and a
  # null parentArg. A nested scope (e.g. a home) reads its config from the
  # owner config at its class's registered `den.classes.<class>.parentPath` —
  # the same route its content is delivered to — and reaches the owner via
  # `parentArg`. This matches the "producing class + scope" rule. Cross-host
  # can't reach a remote real fixpoint, so it leans on the precomputed hostConfigs.
  producerConfigs =
    {
      hostConfigs,
      scopeContexts,
      scopeParent ? { },
      scopeEntityClass ? { },
    }:
    scopeId:
    let
      cls = scopeEntityClass.${scopeId} or null;
      classDef = if cls != null && den.classes ? ${cls} then den.classes.${cls} else { };
      parentArg = classDef.parentArg or null;
    in
    if hostConfigs == null then
      {
        config = { };
        owner = { };
        inherit parentArg;
      }
    else if hostConfigs ? ${scopeId} then
      {
        config = hostConfigs.${scopeId};
        owner = hostConfigs.${scopeId};
        inherit parentArg;
      }
    else
      let
        # Nearest enclosing scope that owns a config.
        findOwner =
          sid:
          if sid == null then
            null
          else if hostConfigs ? ${sid} then
            sid
          else
            findOwner (scopeParent.${sid} or null);
        ownerScope = findOwner (scopeParent.${scopeId} or null);
        ownerCfg = if ownerScope == null then { } else hostConfigs.${ownerScope};
        # The producer's class parentPath locates its config within the owner
        # config — the same route its content is delivered to. No path → it owns
        # its config (but isn't a hostConfigs key here, so resolves to empty).
        pathFn = classDef.parentPath or null;
        ctx = scopeContexts.${scopeId} or { };
        name = ctx.user.name or ctx.home.name or null;
      in
      {
        config = if pathFn != null && name != null then lib.attrByPath (pathFn name) { } ownerCfg else { };
        owner = ownerCfg;
        inherit parentArg;
      };

  # Resolve a config-dependent thunk against the producer's class config.
  # Used for COLLECTED / BROADCAST entries (cross-scope) where the SOURCE
  # scope's config is needed. Provides scope context args (host, user, etc.)
  # alongside `config` (producer class) and, for a nested producer, the owner
  # config under the class's parentArg. Returns a list (auto-flattens lists).
  resolveEntry =
    hostConfigs: producerConfigFor: scopeContexts: sourceScopeId: entry:
    if isConfigDependent entry then
      if hostConfigs == null then
        # No host configs on this crossing path: defer the config-dependent emit.
        # The local evalModules fixpoint resolves it (via __configThunk). Collected
        # config-dependent entries are never marked, so this is a clean pass-through.
        [ entry ]
      else
        let
          thunkArgs = builtins.functionArgs entry;
          scopeCtx = scopeContexts.${sourceScopeId} or { };
          ctxArgs = lib.genAttrs (builtins.filter (k: scopeCtx ? ${k}) (builtins.attrNames thunkArgs)) (
            k: scopeCtx.${k}
          );
          pc = producerConfigFor sourceScopeId;
          result = entry (
            ctxArgs
            // {
              config = pc.config;
            }
            // lib.optionalAttrs (pc.parentArg != null) { ${pc.parentArg} = pc.owner; }
            // {
              inherit lib;
            }
          );
        in
        if builtins.isList result then result else [ result ]
    else if isPipelineParametric entry then
      let
        thunkArgs = builtins.functionArgs entry;
        scopeCtx = scopeContexts.${sourceScopeId} or { };
        ctxArgs = lib.genAttrs (builtins.filter (k: scopeCtx ? ${k}) (builtins.attrNames thunkArgs)) (
          k: scopeCtx.${k}
        );
        result = entry (ctxArgs // { inherit lib; });
      in
      if builtins.isList result then result else [ result ]
    else
      [ entry ];

  # Resolve pipeline-parametric emits eagerly on every crossing path so the
  # value crosses as data, not a function. Config-dependent emits stay deferred
  # (resolved in the evalModules fixpoint via __configThunk) when no hostConfigs.
  resolveThunks =
    hostConfigs: producerConfigFor: scopeContexts: scopeId: values:
    builtins.concatMap (resolveEntry hostConfigs producerConfigFor scopeContexts scopeId) values;

  # Value functor: lets ONE stage interpreter run over either bare values (the
  # plain path) or provenance-tagged values ({ __pv = value; __ps = scopeId; }).
  # Each functor supplies:
  #   unwrap     wrapped -> raw           (read the underlying value)
  #   rewrap     wrapped -> raw -> wrapped (replace value, keep tag — transform)
  #   seed       scopeId -> raw -> wrapped (tag a fresh value at a given scope —
  #                                         fold/append/for re-tag, collect tags
  #                                         each value with its SOURCE scope)
  #   passthrough wrapped -> bool         (skip filter/transform — the plain
  #                                         path passes __configThunk markers
  #                                         through unchanged; provenance never:
  #                                         the legacy provenance interpreter had
  #                                         no __configThunk guard, preserved
  #                                         bug-for-bug — do not "fix")
  idFunctor = {
    unwrap = v: v;
    rewrap = _old: raw: raw;
    seed = _scope: raw: raw;
    passthrough = v: v ? __configThunk;
  };
  pvFunctor = {
    unwrap = v: v.__pv;
    rewrap = old: raw: old // { __pv = raw; };
    seed = scope: raw: {
      __pv = raw;
      __ps = scope;
    };
    passthrough = _v: false;
  };

  # Apply a single filter/transform/fold/append/for stage to a value list,
  # interpreted through `functor`. `currentScopeId` is the scope new values
  # (fold/append/for results) are re-tagged to.
  applyStageWith =
    functor: currentScopeId: values: stage:
    let
      t = stage.__pipeStage or "";
      inherit (functor)
        unwrap
        rewrap
        passthrough
        ;
      seed = functor.seed currentScopeId;
    in
    if t == "filter" then
      builtins.filter (v: passthrough v || stage.fn (unwrap v)) values
    else if t == "transform" then
      map (v: if passthrough v then v else rewrap v (stage.fn (unwrap v))) values
    else if t == "fold" then
      [ (seed (builtins.foldl' (acc: v: stage.fn acc (unwrap v)) stage.init values)) ]
    else if t == "append" then
      values ++ [ (seed stage.value) ]
    else if t == "for" then
      map seed (stage.fn (map unwrap values))
    else
      values;

  # Plain-path single-stage application (identity functor, no provenance tag).
  # Config thunk markers (__configThunk) pass through filter/transform unchanged.
  applyStage = applyStageWith idFunctor null;

  # Apply all transform stages from a pipe effect.
  applyTransformStages =
    values: stages:
    let
      transformStages = builtins.filter (
        s:
        builtins.elem (s.__pipeStage or "") [
          "filter"
          "transform"
          "fold"
          "append"
          "for"
        ]
      ) stages;
    in
    builtins.foldl' applyStage values transformStages;

  # Find sibling scopes matching a predicate.
  # Siblings = scopes sharing the same parent in scopeParent.
  # Entity kind filtering: reject scopes whose entity kinds don't match the predicate.
  findMatchingSiblings =
    {
      scopeContexts,
      scopeParent,
      scopeEntityKind ? { },
      currentScopeId,
    }:
    predicate:
    let
      entityKinds = den.lib.schemaUtil.schemaEntityKinds;
      parent = scopeParent.${currentScopeId} or null;
      allScopeIds = builtins.attrNames scopeContexts;
      siblings = builtins.filter (
        sid: sid != currentScopeId && (scopeParent.${sid} or null) == parent
      ) allScopeIds;
      predArgs = builtins.functionArgs predicate;
      requiredArgs = builtins.filter (k: !predArgs.${k}) (builtins.attrNames predArgs);
      predEntityArgs = builtins.filter (k: builtins.elem k entityKinds) requiredArgs;
      predicateMatches =
        sid:
        let
          ctx = scopeContexts.${sid};
          hasRequired = builtins.all (k: ctx ? ${k}) requiredArgs;
          # Use the scope's own entity kind (what it was created for), not all
          # entity kinds inherited from parent context.  A host scope under an
          # environment has { environment, host } in context but its own entity
          # kind is just "host".  This prevents parent grouping entities from
          # causing false rejections in the depth filter.
          ownKind = scopeEntityKind.${sid} or null;
          scopeOwnEntityKinds =
            if ownKind != null then [ ownKind ] else builtins.filter (k: ctx ? ${k}) entityKinds;
          extraEntityKinds = builtins.filter (k: !builtins.elem k predEntityArgs) scopeOwnEntityKinds;
        in
        hasRequired && extraEntityKinds == [ ] && predicate ctx;
    in
    builtins.filter predicateMatches siblings;

  # Find all scopes matching a predicate, regardless of parent.
  findMatchingAll =
    {
      scopeContexts,
      scopeEntityKind ? { },
      currentScopeId,
    }:
    predicate:
    let
      entityKinds = den.lib.schemaUtil.schemaEntityKinds;
      allScopeIds = builtins.attrNames scopeContexts;
      candidates = builtins.filter (sid: sid != currentScopeId) allScopeIds;
      predArgs = builtins.functionArgs predicate;
      requiredArgs = builtins.filter (k: !predArgs.${k}) (builtins.attrNames predArgs);
      predEntityArgs = builtins.filter (k: builtins.elem k entityKinds) requiredArgs;
      predicateMatches =
        sid:
        let
          ctx = scopeContexts.${sid};
          hasRequired = builtins.all (k: ctx ? ${k}) requiredArgs;
          ownKind = scopeEntityKind.${sid} or null;
          scopeOwnEntityKinds =
            if ownKind != null then [ ownKind ] else builtins.filter (k: ctx ? ${k}) entityKinds;
          extraEntityKinds = builtins.filter (k: !builtins.elem k predEntityArgs) scopeOwnEntityKinds;
        in
        hasRequired && extraEntityKinds == [ ] && predicate ctx;
    in
    builtins.filter predicateMatches candidates;

  # Process stages sequentially, including collect and withProvenance stages.
  # When withProvenance is present, values are internally tagged with source
  # scope IDs: { __pv = value; __ps = scopeId; }. The withProvenance stage
  # converts these to user-visible { value; source; } format.
  #
  # One interpreter, lifted over a value functor (idFunctor for the plain path,
  # pvFunctor when withProvenance is present). filter/transform/fold/append/for
  # go through applyStageWith; collect/collectAll resolve matching scopes and
  # tag each collected value with its SOURCE scope (seed sid), which is the
  # identity for the plain path and the provenance tag for the provenance path.
  processStagesWithCollect =
    {
      scopeContexts,
      scopeParent,
      scopeEntityKind ? { },
      scopedClassImports,
      allExposed ? { },
      scopeEntityClass ? { },
      currentScopeId,
      pipeName,
      hostConfigs ? null,
    }:
    initialValues: stages:
    let
      hasProvenance = builtins.any (s: (s.__pipeStage or "") == "withProvenance") stages;
      functor = if hasProvenance then pvFunctor else idFunctor;
      relevantStages = builtins.filter (
        s:
        builtins.elem (s.__pipeStage or "") [
          "filter"
          "transform"
          "fold"
          "append"
          "for"
          "collect"
          "collectAll"
          "withProvenance"
        ]
      ) stages;
      # Tag initial values at the current scope (identity for the plain path).
      taggedInitial = map (functor.seed currentScopeId) initialValues;
      producerConfigFor = producerConfigs {
        inherit
          hostConfigs
          scopeContexts
          scopeParent
          scopeEntityClass
          ;
      };
      # Resolve a list of matching scopes into collected values, each tagged with
      # its SOURCE scope id (not currentScopeId).
      collectTagged =
        matchingScopes:
        lib.concatMap (
          sid:
          let
            entries = (scopedClassImports.${sid} or { }).${pipeName} or [ ];
            rawValues = flattenAndExtract entries;
            resolved = resolveThunks hostConfigs producerConfigFor scopeContexts sid rawValues;
            # Also collect data that sid's children exposed UP into sid (pipe.expose).
            # collectAllExposed already resolved these at the exposing node, so they
            # cross as concrete data — a peer's collect sees a host's exposed-up
            # user data, not just its raw host-scope emits.
            exposed = (allExposed.${sid} or { }).${pipeName} or [ ];
          in
          map (functor.seed sid) (resolved ++ exposed)
        ) matchingScopes;
    in
    builtins.foldl' (
      values: stage:
      let
        t = stage.__pipeStage or "";
      in
      if t == "collect" then
        values
        ++ collectTagged (
          findMatchingSiblings {
            inherit
              scopeContexts
              scopeParent
              scopeEntityKind
              currentScopeId
              ;
          } stage.fn
        )
      else if t == "collectAll" then
        values
        ++ collectTagged (
          findMatchingAll {
            inherit
              scopeContexts
              scopeEntityKind
              currentScopeId
              ;
          } stage.fn
        )
      else if t == "withProvenance" then
        map (v: {
          value = v.__pv;
          source = scopeContexts.${v.__ps};
        }) values
      else
        applyStageWith functor currentScopeId values stage
    ) taggedInitial relevantStages;

  # Check whether a pipe effect has a pipe.to routing stage.
  hasToStage = e: builtins.any (s: (s.__pipeStage or "") == "to") (e.stages or [ ]);

  # Extract target aspect identity keys from a pipe.to stage.
  # Uses full identity pathkey (e.g., "provider/postgres") not just leaf name.
  getToTargets =
    effect:
    let
      toStage = lib.findFirst (s: (s.__pipeStage or "") == "to") null (effect.stages or [ ]);
    in
    map (a: den.lib.aspects.fx.identity.key a) toStage.aspects;

  # Check whether a pipe effect has a pipe.as renaming stage.
  hasAsStage = e: builtins.any (s: (s.__pipeStage or "") == "as") (e.stages or [ ]);

  # Extract target pipe name from a pipe.as stage.
  getAsTarget =
    e:
    let
      asStage = lib.findFirst (s: (s.__pipeStage or "") == "as") null (e.stages or [ ]);
    in
    if asStage == null then null else asStage.targetPipeName;

  # Filter out pipe.as stage from a stage list (it's a routing directive, not a transform).
  stripAsStage = stages: builtins.filter (s: (s.__pipeStage or "") != "as") stages;

  # Validate pipe.as does not target its own source pipe (would silently drop data).
  assertNoSelfAs =
    effect:
    let
      target = getAsTarget effect;
    in
    if target != null && target == effect.pipeName then
      throw "den: pipe.as targets its own pipe '${effect.pipeName}' — this is a no-op that silently drops data. Remove the pipe.as stage or target a different pipe."
    else
      true;

  # Choose the right stage processor for an effect's stages.
  # Uses processStagesWithCollect when collect or withProvenance stages are present.
  applyEffectStages =
    {
      scopeContexts,
      scopeParent,
      scopeEntityKind ? { },
      scopedClassImports,
      allExposed ? { },
      scopeEntityClass ? { },
      currentScopeId,
      pipeName,
      hostConfigs ? null,
    }:
    baseValues: stages:
    if
      builtins.any (
        s:
        builtins.elem (s.__pipeStage or "") [
          "collect"
          "collectAll"
          "withProvenance"
        ]
      ) stages
    then
      processStagesWithCollect {
        inherit
          scopeContexts
          scopeParent
          scopeEntityKind
          scopedClassImports
          allExposed
          scopeEntityClass
          currentScopeId
          pipeName
          hostConfigs
          ;
      } baseValues stages
    else
      applyTransformStages baseValues stages;

  # Apply pipe effects from policies to a pipe's base values.
  # Returns only the untargeted (scope-wide) result.
  applyPipeEffects =
    {
      scopeContexts,
      scopeParent,
      scopeEntityKind ? { },
      scopedClassImports,
      allExposed ? { },
      scopeEntityClass ? { },
      hostConfigs ? null,
    }:
    pipeName: scopeId: baseValues: effects:
    let
      # Check pipe.for singularity — at most one per pipe per scope.
      forEffects = builtins.filter (
        e: builtins.any (s: (s.__pipeStage or "") == "for") (e.stages or [ ])
      ) effects;
      forCount = builtins.length forEffects;
      _ =
        if forCount > 1 then
          throw "den: multiple pipe.for on '${pipeName}' in scope '${scopeId}' from policies: ${
            lib.concatMapStringsSep ", " (e: e.__pipePolicyName or "<anon>") forEffects
          }"
        else
          null;
      applyStages = applyEffectStages {
        inherit
          scopeContexts
          scopeParent
          scopeEntityKind
          scopedClassImports
          allExposed
          scopeEntityClass
          hostConfigs
          ;
        currentScopeId = scopeId;
        inherit pipeName;
      };
    in
    builtins.seq _ (
      if forCount == 1 then
        applyStages baseValues ((builtins.head forEffects).stages or [ ])
      else
        # Each effect runs independently on the base pool, results concatenated.
        lib.concatLists (map (e: applyStages baseValues (e.stages or [ ])) effects)
    );

  # Build per-aspect targeted pipe data from targeted effects.
  # Returns: { aspectName → transformedValues }
  buildTargetedData =
    {
      scopeContexts,
      scopeParent,
      scopeEntityKind ? { },
      scopedClassImports,
      allExposed ? { },
      scopeEntityClass ? { },
      currentScopeId,
      hostConfigs ? null,
    }:
    baseValues: effects:
    let
      # Collect (aspectName, values) pairs from all targeted effects.
      pairs = lib.concatMap (
        effect:
        let
          targets = getToTargets effect;
          transformed = applyEffectStages {
            inherit
              scopeContexts
              scopeParent
              scopedClassImports
              allExposed
              scopeEntityClass
              currentScopeId
              hostConfigs
              ;
            pipeName = effect.pipeName;
          } baseValues (effect.stages or [ ]);
        in
        map (name: {
          inherit name;
          values = transformed;
        }) targets
      ) effects;
    in
    # Group by aspect name, concatenating values for same aspect.
    builtins.foldl' (
      acc: entry:
      acc
      // {
        ${entry.name} =
          (acc.${entry.name} or [ ])
          ++ (if builtins.isList entry.values then entry.values else [ entry.values ]);
      }
    ) { } pairs;

  # Check whether a pipe effect has a pipe.expose routing stage.
  hasExposeStage = e: builtins.any (s: (s.__pipeStage or "") == "expose") (e.stages or [ ]);

  # Check whether a pipe effect has a pipe.broadcast routing stage.
  hasBroadcastStage = e: builtins.any (s: (s.__pipeStage or "") == "broadcast") (e.stages or [ ]);

  # Extract the receiver predicate from a pipe.broadcast stage.
  getBroadcastPred =
    e:
    let
      bStage = lib.findFirst (s: (s.__pipeStage or "") == "broadcast") null (e.stages or [ ]);
    in
    if bStage == null then null else bStage.fn;

  # Dedup pipe effects by (pipeName, policyName). A policy may fire for several
  # entity kinds in one scope, producing duplicate effects for a single routing
  # — used by the expose (collectAllExposed) and broadcast (collectAllBroadcast)
  # passes, which both fan a scope's routing effects out once.
  dedupEffectsByPolicy =
    let
      go =
        seen: effs:
        if effs == [ ] then
          [ ]
        else
          let
            e = builtins.head effs;
            rest = builtins.tail effs;
            key = "${e.pipeName}/${e.__pipePolicyName or "<anon>"}";
          in
          if seen ? ${key} then go seen rest else [ e ] ++ go (seen // { ${key} = true; }) rest;
    in
    go { };

  # Collect exposed data bottom-up from child scopes.
  # Returns: { parentScopeId → { pipeName → [values] } }
  collectAllExposed =
    {
      scopeContexts,
      scopedClassImports,
      scopedPipeEffects,
      scopeParent,
      scopeEntityClass ? { },
    }:
    let
      allScopeIds = builtins.attrNames scopeContexts;

      # Find children of a given parent scope.
      childrenOf =
        parentId:
        builtins.filter (sid: sid != parentId && (scopeParent.${sid} or null) == parentId) allScopeIds;

      # Recursive bottom-up: process children first, accumulate exposed data.
      processTree =
        exposedPool: scopeId:
        let
          children = childrenOf scopeId;
          # Process all children first.
          afterChildren = builtins.foldl' processTree exposedPool children;
          # Now compute what this scope exposes to its parent.
          parentId = scopeParent.${scopeId} or null;
          isRoot = parentId == null || parentId == scopeId;
          scopeEffects = scopedPipeEffects.${scopeId} or [ ];
          rawExposeEffects = builtins.filter hasExposeStage scopeEffects;
          exposeEffects = dedupEffectsByPolicy rawExposeEffects;
        in
        if isRoot || exposeEffects == [ ] then
          afterChildren
        else
          let
            scopeImports = scopedClassImports.${scopeId} or { };
            # Also include data already exposed to this scope from its children.
            exposedForScope = afterChildren.${scopeId} or { };
            scopeCtx = scopeContexts.${scopeId} or { };
            newExposed = lib.foldl' (
              acc: effect:
              let
                inherit (effect) pipeName;
                rawEntries = scopeImports.${pipeName} or [ ];
                baseValues = flattenAndExtract rawEntries;
                # Resolve pipeline-parametric local emits at the exposing node so the
                # value crosses the P edge upward as data; mark config-dependent emits
                # so they carry __configThunk as they cross (consumers re-mark
                # idempotently via mkCombinedBase, but marking at the source keeps
                # multi-level expose chains correct without relying on every consumer
                # to re-mark). Mirrors mkCombinedBase on the local path.
                resolvedBase = markConfigThunks (producerOf scopeEntityClass scopeContexts scopeId) (
                  builtins.concatMap (resolveLocalParametric scopeCtx) baseValues
                );
                # Child-exposed data is already concrete — each child resolved its
                # own at its own node — so include it as-is for transform stages.
                exposedValues = exposedForScope.${pipeName} or [ ];
                combinedBase = resolvedBase ++ exposedValues;
                transformed = applyTransformStages combinedBase (effect.stages or [ ]);
              in
              acc
              // {
                ${pipeName} = (acc.${pipeName} or [ ]) ++ transformed;
              }
            ) { } exposeEffects;
          in
          afterChildren
          // {
            ${parentId} =
              (removeAttrs (afterChildren.${parentId} or { }) (builtins.attrNames newExposed))
              // lib.mapAttrs (pipeName: vals: (afterChildren.${parentId}.${pipeName} or [ ]) ++ vals) newExposed;
          };

      # Find root scopes to start traversal.
      rootScopes = builtins.filter (
        sid:
        let
          parent = scopeParent.${sid} or null;
        in
        parent == null || parent == sid
      ) allScopeIds;
    in
    builtins.foldl' processTree { } rootScopes;

  # Distribute broadcast data laterally: each broadcaster S pushes its
  # (source-transformed) pipe value to every OTHER scope whose context matches
  # the broadcast predicate. The push dual of pipe.expose (which routes to the
  # parent); mechanically a fan-out gather, so it reuses findMatchingAll's
  # entity-kind filtering and resolveThunks' cross-host config resolution.
  # Source values are the broadcaster's RAW emits — not the post-expose
  # assembled value. The marquee source is a user scope (a leaf with no children
  # to expose); a HOST broadcaster therefore does NOT fold in its users'
  # exposed-up data, an intentional asymmetry with collect's raw+exposed read.
  # Returns: { receiverScopeId → { pipeName → [values] } }
  collectAllBroadcast =
    {
      scopeContexts,
      scopedClassImports,
      scopedPipeEffects,
      scopeParent ? { },
      scopeEntityKind ? { },
      scopeEntityClass ? { },
      hostConfigs ? null,
    }:
    let
      allScopeIds = builtins.attrNames scopeContexts;
      producerConfigFor = producerConfigs {
        inherit
          hostConfigs
          scopeContexts
          scopeParent
          scopeEntityClass
          ;
      };
      perBroadcaster =
        sourceId:
        let
          scopeEffects = scopedPipeEffects.${sourceId} or [ ];
          broadcastEffects = dedupEffectsByPolicy (builtins.filter hasBroadcastStage scopeEffects);
          scopeImports = scopedClassImports.${sourceId} or { };
        in
        lib.concatMap (
          effect:
          let
            inherit (effect) pipeName;
            rawEntries = scopeImports.${pipeName} or [ ];
            baseValues = flattenAndExtract rawEntries;
            # Resolve the source value to data as it crosses to the receiver:
            # pipeline-parametric eagerly, config-dependent against the SOURCE's
            # PRODUCER class config (host→nixos, user/home→home-manager) — NOT
            # deferred, since the receiver may be on another host. Then apply the
            # source-side transform stages (the broadcast routing stage is
            # ignored by applyTransformStages).
            resolvedBase = resolveThunks hostConfigs producerConfigFor scopeContexts sourceId baseValues;
            transformed = applyTransformStages resolvedBase (effect.stages or [ ]);
            receivers = findMatchingAll {
              inherit scopeContexts scopeEntityKind;
              currentScopeId = sourceId;
            } (getBroadcastPred effect);
          in
          map (receiverId: {
            inherit receiverId pipeName;
            values = transformed;
          }) receivers
        ) broadcastEffects;
      allEntries = builtins.concatMap perBroadcaster allScopeIds;
    in
    builtins.foldl' (
      acc: entry:
      let
        existing = acc.${entry.receiverId} or { };
      in
      acc
      // {
        ${entry.receiverId} = existing // {
          ${entry.pipeName} = (existing.${entry.pipeName} or [ ]) ++ entry.values;
        };
      }
    ) { } allEntries;

  assemblePipes =
    {
      scopeContexts,
      scopedClassImports,
      scopedPipeEffects ? { },
      scopeParent ? { },
      scopeEntityKind ? { },
      scopeEntityClass ? { },
      hostConfigs ? null,
    }:
    if pipeNames == [ ] then
      scopeContexts
    else
      let
        # Pass 1: Collect all exposed data bottom-up.
        allExposed = collectAllExposed {
          inherit
            scopeContexts
            scopedClassImports
            scopedPipeEffects
            scopeParent
            scopeEntityClass
            ;
        };

        # Pass 1b: Distribute broadcast data laterally (push, fleet-wide).
        allBroadcast = collectAllBroadcast {
          inherit
            scopeContexts
            scopedClassImports
            scopedPipeEffects
            scopeParent
            scopeEntityKind
            scopeEntityClass
            hostConfigs
            ;
        };

        # A scope binds pipe `pn` locally when it emits it, receives it via
        # pipe.expose, receives a pipe.broadcast targeting it, or runs a pipe
        # policy effect for it. A pure-consumer scope binds nothing and inherits
        # `pn` from the nearest ancestor whose policy bound it — see pipeData
        # below. The broadcast clause keeps a pure-receiver scope (no local emit
        # or effect) from falling through to ancestor inheritance.
        bindsPipeLocally =
          sid: pn:
          ((scopedClassImports.${sid} or { }).${pn} or [ ]) != [ ]
          || ((allExposed.${sid} or { }).${pn} or [ ]) != [ ]
          || ((allBroadcast.${sid} or { }).${pn} or [ ]) != [ ]
          || builtins.any (e: e.pipeName == pn) (scopedPipeEffects.${sid} or [ ]);

        # Nearest ancestor (walking scopeParent) whose pipe policy bound `pn`.
        # That scope's assembled value is the source the consumer inherits.
        policyBoundAncestor =
          sid: pn:
          let
            parent = scopeParent.${sid} or null;
          in
          if parent == null || parent == sid then
            null
          else if builtins.any (e: e.pipeName == pn) (scopedPipeEffects.${parent} or [ ]) then
            parent
          else
            policyBoundAncestor parent pn;
      in
      # Pass 2: Build final contexts with exposed data merged in.
      let
        assembled = lib.mapAttrs (
          scopeId: scopeCtx:
          let
            scopeImports = scopedClassImports.${scopeId} or { };
            scopeEffects = scopedPipeEffects.${scopeId} or [ ];
            exposedForScope = allExposed.${scopeId} or { };

            # Resolve and mark a pipe's base values (imports + exposed), used by pipe.as routing.
            mkCombinedBase =
              pn:
              let
                rawEntries = scopeImports.${pn} or [ ];
                baseValues = flattenAndExtract rawEntries;
                resolvedBase = builtins.concatMap (resolveLocalParametric scopeCtx) baseValues;
                # Own emits are produced at THIS scope; exposed values keep the
                # producer tag set at their exposing node (re-mark is a no-op).
                producer = producerOf scopeEntityClass scopeContexts scopeId;
                markedBase = markConfigThunks producer resolvedBase;
                exposedValues = exposedForScope.${pn} or [ ];
                markedExposed = markConfigThunks producer exposedValues;
              in
              markedBase ++ markedExposed;

            # For each pipe, separate untargeted and targeted effects.
            localPipeData = lib.genAttrs pipeNames (
              pipeName:
              let
                combinedBase = mkCombinedBase pipeName;
                exposedValues = exposedForScope.${pipeName} or [ ];
                relevantEffects = builtins.filter (e: e.pipeName == pipeName) scopeEffects;
                # Validate no pipe.as self-targeting in this scope.
                _asCheck = builtins.deepSeq (map (
                  e:
                  assert assertNoSelfAs e;
                  null
                ) (builtins.filter hasAsStage relevantEffects)) null;
                # Exclude expose, targeted, and pipe.as effects from untargeted processing.
                untargetedEffects = builtins.seq _asCheck (
                  builtins.filter (e: !hasToStage e && !hasExposeStage e && !hasAsStage e) relevantEffects
                );

                # Find pipe.as effects from OTHER pipes that target this pipeName (untargeted only).
                # Exclude pipe.expose effects — they route upward, not laterally.
                asInbound = builtins.filter (
                  e:
                  hasAsStage e
                  && !hasToStage e
                  && !hasExposeStage e
                  && getAsTarget e == pipeName
                  && e.pipeName != pipeName
                ) scopeEffects;

                # Process each inbound pipe.as effect against its SOURCE pipe's base values.
                asResults = lib.concatMap (
                  e:
                  let
                    combinedSrc = mkCombinedBase e.pipeName;
                  in
                  applyEffectStages {
                    inherit
                      scopeContexts
                      scopeParent
                      scopeEntityKind
                      scopedClassImports
                      allExposed
                      scopeEntityClass
                      hostConfigs
                      ;
                    currentScopeId = scopeId;
                    pipeName = e.pipeName;
                  } combinedSrc (stripAsStage (e.stages or [ ]))
                ) asInbound;

                normalResult =
                  if untargetedEffects == [ ] && relevantEffects == [ ] && exposedValues == [ ] then
                    combinedBase
                  else if untargetedEffects == [ ] then
                    # All effects are targeted, expose, or pipe.as — scope-wide data is base values unchanged.
                    combinedBase
                  else
                    applyPipeEffects {
                      inherit
                        scopeContexts
                        scopeParent
                        scopeEntityKind
                        scopedClassImports
                        allExposed
                        scopeEntityClass
                        hostConfigs
                        ;
                    } pipeName scopeId combinedBase untargetedEffects;

                # Values pushed to this scope by peers' pipe.broadcast (S≠R).
                # The source already applied its transform stages, so these are
                # concrete data — appended alongside the scope's own base.
                broadcastReceived = (allBroadcast.${scopeId} or { }).${pipeName} or [ ];
              in
              normalResult ++ asResults ++ broadcastReceived
            );

            # Pure-consumer scopes inherit a pipe's assembled value from the
            # nearest ancestor whose policy bound it. A user/home scope thus reads
            # the host scope's fleet-collected data rather than an empty or
            # self-only local value. Scopes that bind the pipe locally keep theirs.
            pipeData = lib.mapAttrs (
              pipeName: localVal:
              if bindsPipeLocally scopeId pipeName then
                localVal
              else
                let
                  anc = policyBoundAncestor scopeId pipeName;
                in
                if anc != null then assembled.${anc}.${pipeName} or localVal else localVal
            ) localPipeData;

            # Build __pipeTargeted: { aspectName → { pipeName → values } }
            pipeTargeted =
              let
                perPipe = lib.genAttrs pipeNames (
                  pipeName:
                  let
                    combinedBase = mkCombinedBase pipeName;
                    relevantEffects = builtins.filter (e: e.pipeName == pipeName) scopeEffects;
                    # Targeted effects on this pipe WITHOUT pipe.as (they stay under this pipeName).
                    targetedEffects = builtins.filter (e: hasToStage e && !hasAsStage e) relevantEffects;

                    # Targeted pipe.as effects from OTHER pipes that rename to this pipeName.
                    # Exclude pipe.expose effects — they route upward, not laterally.
                    asTargetedInbound = builtins.filter (
                      e:
                      hasAsStage e
                      && hasToStage e
                      && !hasExposeStage e
                      && getAsTarget e == pipeName
                      && e.pipeName != pipeName
                    ) scopeEffects;

                    # Build targeted data from native targeted effects.
                    nativeTargeted =
                      if targetedEffects == [ ] then
                        { }
                      else
                        buildTargetedData {
                          inherit
                            scopeContexts
                            scopeParent
                            scopeEntityKind
                            scopedClassImports
                            allExposed
                            scopeEntityClass
                            hostConfigs
                            ;
                          currentScopeId = scopeId;
                        } combinedBase targetedEffects;

                    # Build targeted data from inbound pipe.as effects (using source pipe's base).
                    asTargetedResults = lib.foldl' (
                      acc: e:
                      let
                        combinedSrc = mkCombinedBase e.pipeName;
                        result = buildTargetedData {
                          inherit
                            scopeContexts
                            scopeParent
                            scopeEntityKind
                            scopedClassImports
                            allExposed
                            scopeEntityClass
                            hostConfigs
                            ;
                          currentScopeId = scopeId;
                        } combinedSrc [ (e // { stages = stripAsStage (e.stages or [ ]); }) ];
                      in
                      # Merge: concatenate values per aspect name.
                      lib.foldl' (
                        a: aspectName: a // { ${aspectName} = (a.${aspectName} or [ ]) ++ result.${aspectName}; }
                      ) acc (builtins.attrNames result)
                    ) { } asTargetedInbound;

                  in
                  # Merge native targeted + inbound pipe.as targeted.
                  lib.foldl' (
                    acc: aspectName:
                    acc // { ${aspectName} = (acc.${aspectName} or [ ]) ++ (asTargetedResults.${aspectName} or [ ]); }
                  ) nativeTargeted (builtins.attrNames asTargetedResults)
                );
                # Invert: { pipeName → { aspectName → vals } } → { aspectName → { pipeName → vals } }
                allAspectNames = lib.unique (
                  lib.concatMap (pipeName: builtins.attrNames (perPipe.${pipeName})) pipeNames
                );
              in
              lib.genAttrs allAspectNames (
                aspectName:
                lib.genAttrs (builtins.filter (pn: perPipe.${pn} ? ${aspectName}) pipeNames) (
                  pipeName: perPipe.${pipeName}.${aspectName}
                )
              );

            hasTargeted = pipeTargeted != { };

            # Flag pipes that contain config thunk markers for resolution
            # inside evalModules (see class-module.nix wrapFunctionModule).
            pipeConfigThunks = lib.genAttrs (builtins.filter (
              pipeName: builtins.any (v: v ? __configThunk) (pipeData.${pipeName})
            ) pipeNames) (_: true);
            hasConfigThunks = pipeConfigThunks != { };
          in
          scopeCtx
          // pipeData
          // lib.optionalAttrs hasTargeted { __pipeTargeted = pipeTargeted; }
          // lib.optionalAttrs hasConfigThunks { __pipeConfigThunks = pipeConfigThunks; }
        ) scopeContexts;
      in
      assembled;
in
{
  inherit assemblePipes;
}
