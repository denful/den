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
    "__parametricResolved"
    "_module"
    "_"
  ] (_: true);

  # Schema registry for key classification.
  # Top-level den.classes lives outside den.schema, breaking
  # the evaluation cycle that existed when it lived inside den.schema.
  classRegistry = den.classes or { };

  # Depth-limited recursive check: does val contain recognized class sub-keys?
  hasRecognizedSubKeys =
    depth: val:
    builtins.isAttrs val
    && builtins.any (
      sk: classRegistry ? ${sk} || (depth > 0 && hasRecognizedSubKeys (depth - 1) val.${sk})
    ) (builtins.attrNames val);

  # Classify a single non-class key as nested (has recognized sub-keys) or unregistered.
  classifyNonClassKey =
    aspect: k:
    let
      innerValue = den.lib.aspects.fx.contentUtil.unwrapContentValuesForClassification aspect.${k};
    in
    if hasRecognizedSubKeys 3 innerValue then "nested" else "unregistered";

  # Classify non-structural keys: class → nested → unregistered.
  classifyKeys =
    targetClass: aspect:
    let
      allKeys = builtins.filter (k: !(structuralKeysSet ? ${k})) (builtins.attrNames aspect);
    in
    if classRegistry == { } then
      { classKeys = allKeys; nestedKeys = [ ]; unregisteredClassKeys = [ ]; }
    else
      let
        isClassKey = k: classRegistry ? ${k} || (targetClass != null && k == targetClass);
        classKeys = builtins.filter isClassKey allKeys;
        nonClassKeys = builtins.filter (k: !isClassKey k) allKeys;
        classified = lib.partition (k: classifyNonClassKey aspect k == "nested") nonClassKeys;
      in
      {
        inherit classKeys;
        nestedKeys = classified.right;
        unregisteredClassKeys = classified.wrong;
      };
in
{
  inherit structuralKeysSet classifyKeys;
}
