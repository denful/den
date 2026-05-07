{
  lib,
  den,
  ...
}:
let
  # Structural keys are always handled by the pipeline itself — not
  # dispatched as class or nested aspect keys.
  structuralKeysSet = lib.genAttrs [
    "name"
    "description"
    "meta"
    "includes"
    "provides"
    "policies"
    "into"
    "classes"
    "__fn"
    "__args"
    "__functor"
    "__functionArgs"
    "__scopeHandlers"
    "__ctxId"
    "__entityKind"
    "__parametricResolvedArgs"
    "_module"
    "_"
  ] (_: true);

  # Schema registry for key classification.
  # Top-level den.classes lives outside den.schema, breaking
  # the evaluation cycle that existed when it lived inside den.schema.
  classRegistry = den.classes or { };

  # Pipe registry — pipe keys flow through emit-class but are not
  # wrapped as class modules by wrapCollectedClasses.
  pipeRegistry = den.quirks or { };

  hasRecognizedSubKeys =
    depth: val:
    builtins.isAttrs val
    && builtins.any (
      sk: classRegistry ? ${sk} || (depth > 0 && hasRecognizedSubKeys (depth - 1) val.${sk})
    ) (builtins.attrNames val);

  isNestedKey =
    aspect: k:
    hasRecognizedSubKeys 3 (
      den.lib.aspects.fx.contentUtil.unwrapContentValuesForClassification aspect.${k}
    );

  classifyKeys =
    targetClass: aspect:
    let
      allKeys = builtins.filter (k: !(structuralKeysSet ? ${k})) (builtins.attrNames aspect);
    in
    if classRegistry == { } && pipeRegistry == { } then
      {
        classKeys = allKeys;
        nestedKeys = [ ];
        unregisteredClassKeys = [ ];
        pipeKeys = [ ];
      }
    else
      let
        isPipeKey = k: pipeRegistry ? ${k};
        isClassKey = k: classRegistry ? ${k} || (targetClass != null && k == targetClass);
        pipeKeys = builtins.filter isPipeKey allKeys;
        nonPipeKeys = builtins.filter (k: !isPipeKey k) allKeys;
        classKeys = builtins.filter isClassKey nonPipeKeys;
        nonClassKeys = builtins.filter (k: !isClassKey k) nonPipeKeys;
        classified = lib.partition (isNestedKey aspect) nonClassKeys;
      in
      {
        inherit classKeys pipeKeys;
        nestedKeys = classified.right;
        unregisteredClassKeys = classified.wrong;
      };
in
{
  inherit structuralKeysSet classifyKeys pipeRegistry;
}
