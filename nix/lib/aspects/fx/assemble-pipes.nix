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

  # Detect config-dependent thunks: functions that take `config` as an argument.
  # Config-dependent thunks require `config` in their args and are resolved
  # lazily against instantiated host configs.
  isConfigDependent = val: builtins.isFunction val && (builtins.functionArgs val) ? config;

  # Pipeline-parametric values require pipeline context args (host, user, etc.)
  # but not config. These are resolved eagerly using scope context.
  isPipelineParametric = val: builtins.isFunction val && !(builtins.functionArgs val) ? config;

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
  # The marker is transparent to the module wrapper, which resolves it
  # using the evalModules fixpoint config.
  markConfigThunk =
    v:
    if isConfigDependent v then
      {
        __configThunk = true;
        __fn = v;
      }
    else
      v;

  # Mark all config-dependent entries in a value list.
  markConfigThunks = map markConfigThunk;

  # Resolve a config-dependent thunk against instantiated host configs.
  # Used for COLLECTED entries (cross-host) where the source host's config
  # is needed. Provides scope context args (host, user, etc.) alongside config.
  # Returns a list (auto-flattens list-valued results).
  resolveEntry =
    hostConfigs: scopeContexts: sourceScopeId: entry:
    if isConfigDependent entry then
      let
        thunkArgs = builtins.functionArgs entry;
        scopeCtx = scopeContexts.${sourceScopeId} or { };
        ctxArgs = lib.genAttrs (builtins.filter (k: scopeCtx ? ${k}) (builtins.attrNames thunkArgs)) (
          k: scopeCtx.${k}
        );
        result = entry (
          ctxArgs
          // {
            config = hostConfigs.${sourceScopeId} or { };
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

  # Resolve all config-dependent thunks in a list of values.
  # Only used for collected entries (cross-host resolution).
  resolveThunks =
    hostConfigs: scopeContexts: scopeId: values:
    if hostConfigs == null then
      values
    else
      builtins.concatMap (resolveEntry hostConfigs scopeContexts scopeId) values;

  # Apply a single transform stage to a value list.
  # Config thunk markers (__configThunk) pass through filter/transform unchanged.
  applyStage =
    values: stage:
    let
      t = stage.__pipeStage or "";
    in
    if t == "filter" then
      builtins.filter (v: v ? __configThunk || stage.fn v) values
    else if t == "transform" then
      map (v: if v ? __configThunk then v else stage.fn v) values
    else if t == "fold" then
      [ (builtins.foldl' stage.fn stage.init values) ]
    else if t == "append" then
      values ++ [ stage.value ]
    else if t == "for" then
      stage.fn values
    else
      values;

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

  # Collect quirks from all scopes matching a predicate (no parent constraint).
  collectFromAll =
    {
      scopeContexts,
      scopeEntityKind ? { },
      scopedClassImports,
      currentScopeId,
      pipeName,
      hostConfigs ? null,
    }:
    predicate:
    let
      matchingScopes = findMatchingAll {
        inherit
          scopeContexts
          scopeEntityKind
          currentScopeId
          ;
      } predicate;
    in
    lib.concatMap (
      sid:
      let
        entries = (scopedClassImports.${sid} or { }).${pipeName} or [ ];
        values = flattenAndExtract entries;
      in
      resolveThunks hostConfigs scopeContexts sid values
    ) matchingScopes;

  # Collect quirks from sibling scopes matching a predicate.
  collectFromPeers =
    {
      scopeContexts,
      scopeParent,
      scopeEntityKind ? { },
      scopedClassImports,
      currentScopeId,
      pipeName,
      hostConfigs ? null,
    }:
    predicate:
    let
      matchingScopes = findMatchingSiblings {
        inherit
          scopeContexts
          scopeParent
          scopeEntityKind
          currentScopeId
          ;
      } predicate;
    in
    lib.concatMap (
      sid:
      let
        entries = (scopedClassImports.${sid} or { }).${pipeName} or [ ];
        values = flattenAndExtract entries;
      in
      resolveThunks hostConfigs scopeContexts sid values
    ) matchingScopes;

  # Process stages sequentially, including collect and withProvenance stages.
  # When withProvenance is present, values are internally tagged with source
  # scope IDs: { __pv = value; __ps = scopeId; }. The withProvenance stage
  # converts these to user-visible { value; source; } format.
  processStagesWithCollect =
    {
      scopeContexts,
      scopeParent,
      scopeEntityKind ? { },
      scopedClassImports,
      currentScopeId,
      pipeName,
      hostConfigs ? null,
    }:
    initialValues: stages:
    let
      hasProvenance = builtins.any (s: (s.__pipeStage or "") == "withProvenance") stages;
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
      taggedInitial =
        if hasProvenance then
          map (v: {
            __pv = v;
            __ps = currentScopeId;
          }) initialValues
        else
          initialValues;
    in
    builtins.foldl' (
      values: stage:
      let
        t = stage.__pipeStage or "";
      in
      if t == "collect" then
        if hasProvenance then
          let
            matchingScopes = findMatchingSiblings {
              inherit
                scopeContexts
                scopeParent
                scopeEntityKind
                currentScopeId
                ;
            } stage.fn;
            collected = lib.concatMap (
              sid:
              let
                entries = (scopedClassImports.${sid} or { }).${pipeName} or [ ];
                rawValues = flattenAndExtract entries;
                resolved = resolveThunks hostConfigs scopeContexts sid rawValues;
              in
              map (v: {
                __pv = v;
                __ps = sid;
              }) resolved
            ) matchingScopes;
          in
          values ++ collected
        else
          values
          ++ collectFromPeers {
            inherit
              scopeContexts
              scopeParent
              scopeEntityKind
              scopedClassImports
              currentScopeId
              pipeName
              hostConfigs
              ;
          } stage.fn
      else if t == "collectAll" then
        if hasProvenance then
          let
            matchingScopes = findMatchingAll {
              inherit
                scopeContexts
                scopeEntityKind
                currentScopeId
                ;
            } stage.fn;
            collected = lib.concatMap (
              sid:
              let
                entries = (scopedClassImports.${sid} or { }).${pipeName} or [ ];
                rawValues = flattenAndExtract entries;
                resolved = resolveThunks hostConfigs scopeContexts sid rawValues;
              in
              map (v: {
                __pv = v;
                __ps = sid;
              }) resolved
            ) matchingScopes;
          in
          values ++ collected
        else
          values
          ++ collectFromAll {
            inherit
              scopeContexts
              scopeEntityKind
              scopedClassImports
              currentScopeId
              pipeName
              hostConfigs
              ;
          } stage.fn
      else if t == "withProvenance" then
        map (v: {
          value = v.__pv;
          source = scopeContexts.${v.__ps};
        }) values
      else if hasProvenance then
        if t == "filter" then
          builtins.filter (v: stage.fn v.__pv) values
        else if t == "transform" then
          map (v: v // { __pv = stage.fn v.__pv; }) values
        else if t == "fold" then
          [
            {
              __pv = builtins.foldl' (acc: v: stage.fn acc v.__pv) stage.init values;
              __ps = currentScopeId;
            }
          ]
        else if t == "append" then
          values
          ++ [
            {
              __pv = stage.value;
              __ps = currentScopeId;
            }
          ]
        else if t == "for" then
          map (v: {
            __pv = v;
            __ps = currentScopeId;
          }) (stage.fn (map (v: v.__pv) values))
        else
          values
      else
        applyStage values stage
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

  # Collect exposed data bottom-up from child scopes.
  # Returns: { parentScopeId → { pipeName → [values] } }
  collectAllExposed =
    {
      scopeContexts,
      scopedClassImports,
      scopedPipeEffects,
      scopeParent,
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
          # Dedup expose effects by (pipeName, policyName) — policies may fire
          # for multiple entity kinds in the same scope, producing duplicates.
          exposeEffects =
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
            go { } rawExposeEffects;
        in
        if isRoot || exposeEffects == [ ] then
          afterChildren
        else
          let
            scopeImports = scopedClassImports.${scopeId} or { };
            # Also include data already exposed to this scope from its children.
            exposedForScope = afterChildren.${scopeId} or { };
            newExposed = lib.foldl' (
              acc: effect:
              let
                inherit (effect) pipeName;
                rawEntries = scopeImports.${pipeName} or [ ];
                baseValues = flattenAndExtract rawEntries;
                # Include child-exposed data in the base for transform stages.
                exposedValues = exposedForScope.${pipeName} or [ ];
                combinedBase = baseValues ++ exposedValues;
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

  assemblePipes =
    {
      scopeContexts,
      scopedClassImports,
      scopedPipeEffects ? { },
      scopeParent ? { },
      scopeEntityKind ? { },
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
            ;
        };
      in
      # Pass 2: Build final contexts with exposed data merged in.
      lib.mapAttrs (
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
              markedBase = markConfigThunks resolvedBase;
              exposedValues = exposedForScope.${pn} or [ ];
              markedExposed = markConfigThunks exposedValues;
            in
            markedBase ++ markedExposed;

          # For each pipe, separate untargeted and targeted effects.
          pipeData = lib.genAttrs pipeNames (
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
                      hostConfigs
                      ;
                  } pipeName scopeId combinedBase untargetedEffects;
            in
            normalResult ++ asResults
          );

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
{
  inherit assemblePipes;
}
