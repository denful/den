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

  # Apply pipe effects from policies to a pipe's base values.
  applyPipeEffects =
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
    in
    builtins.seq _ (
      if forCount == 1 then
        # pipe.for takes ownership — other effects for this pipe in this scope
        # are silently dropped. pipe.for semantically replaces the entire pool
        # with an arbitrary value, so filtering/appending from other effects
        # would be incoherent. Use a single policy with pipe.for per pipe.
        applyTransformStages baseValues ((builtins.head forEffects).stages or [ ])
      else
        # Each effect runs independently on the base pool, results concatenated.
        lib.concatLists (map (e: applyTransformStages baseValues (e.stages or [ ])) effects)
    );

  assemblePipes =
    {
      scopeContexts,
      scopedClassImports,
      scopedPipeEffects ? { },
    }:
    if pipeNames == [ ] then
      scopeContexts
    else
      lib.mapAttrs (
        scopeId: scopeCtx:
        let
          scopeImports = scopedClassImports.${scopeId} or { };
          scopeEffects = scopedPipeEffects.${scopeId} or [ ];
          pipeData = lib.genAttrs pipeNames (
            pipeName:
            let
              rawEntries = scopeImports.${pipeName} or [ ];
              baseValues = flattenAndExtract rawEntries;
              relevantEffects = builtins.filter (e: e.pipeName == pipeName) scopeEffects;
            in
            if relevantEffects == [ ] then
              baseValues
            else
              applyPipeEffects pipeName scopeId baseValues relevantEffects
          );
        in
        scopeCtx // pipeData
      ) scopeContexts;
in
{
  inherit assemblePipes;
}
