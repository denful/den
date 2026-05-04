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

  # Classify non-structural keys using the schema registry.
  # 3-step: class → nested aspect → unregistered class.
  # When the registry is empty (no batteries), fall back to treating
  # all non-structural keys as classes for backward compatibility.
  classifyKeys =
    targetClass: aspect:
    let
      allKeys = builtins.filter (k: !(structuralKeysSet ? ${k})) (builtins.attrNames aspect);
      isEmpty = classRegistry == { };
    in
    if isEmpty then
      {
        classKeys = allKeys;
        nestedKeys = [ ];
        unregisteredClassKeys = [ ];
      }
    else
      let
        partition =
          builtins.foldl'
            (
              acc: k:
              if classRegistry ? ${k} || (targetClass != null && k == targetClass) then
                acc // { classKeys = acc.classKeys ++ [ k ]; }
              else
                let
                  rawValue = aspect.${k};
                  # Unwrap aspectContentType to inspect sub-keys.
                  # Multi-site defs: merge all attrset values for detection.
                  innerValue = den.lib.aspects.fx.contentUtil.unwrapContentValuesForClassification rawValue;
                  # Check if any sub-key is a registered class, or if any
                  # sub-key is itself an attrset containing recognized keys
                  # (multi-level nesting detection, depth-limited to 3).
                  hasRecognizedSubKeysAt =
                    depth: val:
                    builtins.isAttrs val
                    && builtins.any (
                      sk: classRegistry ? ${sk} || (depth > 0 && hasRecognizedSubKeysAt (depth - 1) val.${sk})
                    ) (builtins.attrNames val);
                  hasRecognizedSubKeys = hasRecognizedSubKeysAt 3 innerValue;
                in
                if hasRecognizedSubKeys then
                  acc // { nestedKeys = acc.nestedKeys ++ [ k ]; }
                else
                  # Unknown key with no recognized sub-keys — treat as class
                  # (backward compat) but emit trace warning for future migration.
                  acc // { unregisteredClassKeys = acc.unregisteredClassKeys ++ [ k ]; }
            )
            {
              classKeys = [ ];
              nestedKeys = [ ];
              unregisteredClassKeys = [ ];
            }
            allKeys;
      in
      partition;
in
{
  inherit structuralKeysSet classifyKeys;
}
