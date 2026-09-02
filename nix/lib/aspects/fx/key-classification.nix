{
  lib,
  den,
  ...
}:
let
  # Structural keys are always handled by the pipeline itself — not
  # dispatched as class or nested aspect keys.
  builtinStructuralKeys = [
    "name"
    "description"
    "meta"
    "includes"
    "excludes"
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
    "__contentValues"
    "__aspectChain"
    "__providesForwarded"
    "_module"
    "_"
  ];

  # User-extensible reserved keys via den.reservedKeys option.
  structuralKeysSet = lib.genAttrs (builtinStructuralKeys ++ (den.reservedKeys or [ ])) (_: true);

  # Schema registry for key classification.
  # Top-level den.classes lives outside den.schema, breaking
  # the evaluation cycle that existed when it lived inside den.schema.
  classRegistry = den.classes or { };

  # Pipe registry — pipe keys flow through emit-class but are not
  # wrapped as class modules by wrapCollectedClasses.
  pipeRegistry = den.quirks or { };

  # Check whether a value looks like class content (a module or config attrset)
  # rather than plain data.  Rejects flat-scalar attrsets like { name = "…"; }
  # that happen to sit under a key matching a registered class name.
  looksLikeClassContent =
    v:
    lib.isFunction v
    || (builtins.isAttrs v && v ? __contentValues)
    || (
      builtins.isAttrs v
      && builtins.any (k: builtins.isAttrs v.${k} || lib.isFunction v.${k}) (builtins.attrNames v)
    );

  # A nested aspect carries aspect *structure*: a registered class key (with
  # class-like content), a pipe key, or a structural aspect key
  # (includes/provides/meta/…).  Detection inspects attr NAMES only and forces
  # a sub-value solely when its name matches a registered class — never under
  # arbitrary content keys.  Forcing content here would evaluate user values
  # mid-pipeline; a value reading the flake's own `self.outputs` would then
  # re-enter the flake `self` fixpoint → infinite recursion (#580).
  #
  # Depth-1 suffices: sub-aspects are never auto-walked (see compile-static) —
  # they activate via explicit `includes`, so every nested aspect exposes a
  # recognized key at its own top level (a class key or `includes`).
  isNestedKey =
    aspect: k:
    let
      val = den.lib.aspects.fx.contentUtil.unwrapContentValuesForClassification aspect.${k};
    in
    builtins.isAttrs val
    && builtins.any (
      sk:
      structuralKeysSet ? ${sk}
      || pipeRegistry ? ${sk}
      || (classRegistry ? ${sk} && looksLikeClassContent val.${sk})
    ) (builtins.attrNames val);

  classifyKeys =
    targetClass: aspect:
    let
      forwardedSet = lib.genAttrs (aspect.__providesForwarded or [ ]) (_: true);
      allKeys = builtins.filter (k: !(structuralKeysSet ? ${k}) && !(forwardedSet ? ${k})) (
        builtins.attrNames aspect
      );
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
