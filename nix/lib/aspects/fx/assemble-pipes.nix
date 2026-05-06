# Post-pipeline phase: assemble pipe data from scopedClassImports
# and inject into scope contexts for delivery via wrapClassModule.
{
  lib,
  den,
  ...
}:
let
  pipeRegistry = den.pipes or { };
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

  # Apply a single transform stage to a value list.
  applyStage =
    values: stage:
    let
      t = stage.__pipeStage or "";
    in
    if t == "filter" then
      builtins.filter stage.fn values
    else if t == "transform" then
      map stage.fn values
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

  # Collect quirks from peer scopes matching a predicate.
  # Uses the global pipe pool (all hosts' raw data) for cross-host harvesting.
  # Returns flat list of harvested values from matching peers.
  collectFromPeers =
    {
      globalPipePool,
      currentScopeId,
      pipeName,
    }:
    predicate:
    let
      allScopes = builtins.attrNames globalPipePool.scopeContexts;
      # Check if the scope context satisfies the predicate's required args.
      # Entity kind filtering is implicit in the destructuring — if the
      # predicate requires { host, ... } but the scope has no host, skip it.
      predArgs = builtins.functionArgs predicate;
      requiredArgs = builtins.filter (k: !predArgs.${k}) (builtins.attrNames predArgs);
      predicateMatches =
        sid:
        let
          ctx = globalPipePool.scopeContexts.${sid};
          hasRequired = builtins.all (k: ctx ? ${k}) requiredArgs;
        in
        hasRequired && predicate ctx;
      matchingScopes = builtins.filter (sid: sid != currentScopeId && predicateMatches sid) allScopes;
    in
    lib.concatMap (
      sid:
      let
        entries = (globalPipePool.scopedClassImports.${sid} or { }).${pipeName} or [ ];
      in
      flattenAndExtract entries
    ) matchingScopes;

  # Process stages sequentially, including collect stages that harvest from peers.
  # This replaces applyTransformStages for effects that contain collect stages.
  processStagesWithCollect =
    {
      globalPipePool,
      currentScopeId,
      pipeName,
    }:
    initialValues: stages:
    let
      relevantStages = builtins.filter (
        s:
        builtins.elem (s.__pipeStage or "") [
          "filter"
          "transform"
          "fold"
          "append"
          "for"
          "collect"
        ]
      ) stages;
    in
    builtins.foldl' (
      values: stage:
      let
        t = stage.__pipeStage or "";
      in
      if t == "collect" then
        values
        ++ collectFromPeers {
          inherit
            globalPipePool
            currentScopeId
            pipeName
            ;
        } stage.fn
      else
        applyStage values stage
    ) initialValues relevantStages;

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

  # Choose the right stage processor for an effect's stages.
  # Uses processStagesWithCollect when collect stages are present, otherwise applyTransformStages.
  applyEffectStages =
    {
      globalPipePool,
      currentScopeId,
      pipeName,
    }:
    baseValues: stages:
    if builtins.any (s: (s.__pipeStage or "") == "collect") stages then
      processStagesWithCollect {
        inherit
          globalPipePool
          currentScopeId
          pipeName
          ;
      } baseValues stages
    else
      applyTransformStages baseValues stages;

  # Apply pipe effects from policies to a pipe's base values.
  # Returns only the untargeted (scope-wide) result.
  applyPipeEffects =
    {
      globalPipePool,
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
        inherit globalPipePool;
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
      globalPipePool,
      currentScopeId,
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
              globalPipePool
              currentScopeId
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
      globalPipePool ? {
        scopeContexts = { };
        scopedClassImports = { };
      },
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

          # For each pipe, separate untargeted and targeted effects.
          pipeData = lib.genAttrs pipeNames (
            pipeName:
            let
              rawEntries = scopeImports.${pipeName} or [ ];
              baseValues = flattenAndExtract rawEntries;
              # Merge exposed data from children.
              exposedValues = exposedForScope.${pipeName} or [ ];
              combinedBase = baseValues ++ exposedValues;
              relevantEffects = builtins.filter (e: e.pipeName == pipeName) scopeEffects;
              # Exclude expose effects from untargeted processing — they route upward, not locally.
              untargetedEffects = builtins.filter (e: !hasToStage e && !hasExposeStage e) relevantEffects;
            in
            if untargetedEffects == [ ] && relevantEffects == [ ] && exposedValues == [ ] then
              baseValues
            else if untargetedEffects == [ ] then
              # All effects are targeted/expose — scope-wide data is combined base values.
              combinedBase
            else
              applyPipeEffects {
                inherit globalPipePool;
              } pipeName scopeId combinedBase untargetedEffects
          );

          # Build __pipeTargeted: { aspectName → { pipeName → values } }
          pipeTargeted =
            let
              perPipe = lib.genAttrs pipeNames (
                pipeName:
                let
                  rawEntries = scopeImports.${pipeName} or [ ];
                  baseValues = flattenAndExtract rawEntries;
                  exposedValues = exposedForScope.${pipeName} or [ ];
                  combinedBase = baseValues ++ exposedValues;
                  relevantEffects = builtins.filter (e: e.pipeName == pipeName) scopeEffects;
                  targetedEffects = builtins.filter hasToStage relevantEffects;
                in
                if targetedEffects == [ ] then
                  { }
                else
                  buildTargetedData {
                    inherit globalPipePool;
                    currentScopeId = scopeId;
                  } combinedBase targetedEffects
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
        in
        scopeCtx // pipeData // lib.optionalAttrs hasTargeted { __pipeTargeted = pipeTargeted; }
      ) scopeContexts;
in
{
  inherit assemblePipes;
}
