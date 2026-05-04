{
  lib,
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;
  inherit (den.lib.aspects) isMeaningfulName;

  inherit (den.lib.aspects.fx.keyClassification) structuralKeysSet classifyKeys;
  inherit (import ./class-module.nix { inherit lib den; }) wrapClassModule;

  ctxFromHandlers =
    handlers:
    lib.mapAttrs (
      _: handler:
      (handler {
        param = null;
        state = { };
      }).resume
    ) handlers;

  inherit (import ./aspect { inherit lib den; } { inherit ctxFromHandlers; })
    emitIncludes
    emitAspectPolicies
    registerConstraints
    ;

  installPolicies =
    (import ./policy { inherit lib den; } { inherit aspectToEffect ctxFromHandlers; })
    .installPolicies;

  # --- Class emission ---

  # Determine if an aspect's class modules are context-dependent.
  isContextDep =
    aspect: ctx:
    let
      resolvedArgs = aspect.__parametricResolvedArgs or [ ];
    in
    (resolvedArgs != [ ] && builtins.any (ak: ctx ? ${ak}) resolvedArgs)
    || (aspect.meta.contextDependent or false);

  # Emit a single class module entry.
  emitClassEntry =
    { class, identity, module, ctx, aspectPolicy, globalPolicy, isContextDependent }:
    fx.send "emit-class" {
      inherit class identity module ctx aspectPolicy globalPolicy isContextDependent;
      __rawEntry = true;
    };

  # Emit all class entries for a single key (unwraps multi-value content).
  emitClassKey =
    aspect: ctx: aspectPolicy: globalPolicy: contextDep: nodeIdentity: k:
    let
      modules = den.lib.aspects.fx.contentUtil.unwrapContentValuesList aspect.${k};
      isMulti = builtins.length modules > 1;
      mkEntry = idx: module:
        emitClassEntry {
          class = k;
          identity = if isMulti then "${nodeIdentity}[${toString idx}]" else nodeIdentity;
          inherit module ctx aspectPolicy globalPolicy;
          isContextDependent = contextDep;
        };
    in
    fx.seq (lib.imap0 mkEntry modules);

  # Emit all class keys for an aspect.
  emitClasses =
    aspect: classKeys: nodeIdentity:
    let
      ctx = ctxFromHandlers (aspect.__scopeHandlers or { });
      aspectPolicy = aspect.meta.collisionPolicy or null;
      globalPolicy = den.config.classModuleCollisionPolicy or "error";
      contextDep = isContextDep aspect ctx;
    in
    fx.seq (map (emitClassKey aspect ctx aspectPolicy globalPolicy contextDep nodeIdentity) classKeys);

  # --- Tree walk ---

  chainWrap =
    nodeIdentity: isMeaningful: comp:
    if isMeaningful then
      fx.bind (fx.send "chain-push" { identity = nodeIdentity; }) (
        _: fx.bind comp (result: fx.bind (fx.send "chain-pop" null) (_: fx.pure result))
      )
    else
      comp;

  # Build a nested sub-aspect from a freeform key and recurse.
  emitNestedAspect =
    aspect: k:
    let
      innerValue = den.lib.aspects.fx.contentUtil.unwrapContentValuesRaw aspect.${k};
      subAspect =
        (if builtins.isAttrs innerValue then innerValue else { })
        // {
          name = k;
          meta = (aspect.meta or { }) // {
            provider = (aspect.meta.provider or [ ]) ++ [ (aspect.name or "<anon>") ];
          };
        }
        // lib.optionalAttrs (aspect ? __scopeHandlers) { inherit (aspect) __scopeHandlers; }
        // lib.optionalAttrs (aspect ? __ctxId) { inherit (aspect) __ctxId; };
    in
    aspectToEffect subAspect;

  # Run the child resolution sequence: policies → includes → entity policies.
  resolveChildSequence =
    aspect:
    let
      emitCtx = {
        __parentScopeHandlers = aspect.__scopeHandlers or null;
        __parentCtxId = aspect.__ctxId or null;
      };
    in
    fx.bind (emitAspectPolicies aspect) (
      selfProvResults:
      fx.bind (emitIncludes emitCtx (aspect.includes or [ ])) (
        includeResults:
        if !(aspect ? __entityKind) then
          fx.pure (selfProvResults ++ includeResults)
        else
          fx.bind (installPolicies aspect) (
            policyResults: fx.pure (selfProvResults ++ includeResults ++ policyResults)
          )
      )
    );

  # Resolve children with chain tracking and resolve-complete emission.
  resolveChildren =
    aspect:
    { isMeaningful, chainIdentity }:
    fx.bind (chainWrap chainIdentity isMeaningful (resolveChildSequence aspect)) (
      allChildren:
      let
        resolved = aspect // { includes = allChildren; };
      in
      fx.bind (fx.send "resolve-complete" resolved) (_: fx.pure resolved)
    );

  # --- Static compilation ---

  compileStatic =
    aspect:
    let
      nodeIdentity = identity.key aspect;
      chainIdentity = identity.pathKey ((aspect.meta.provider or [ ]) ++ [ (aspect.name or "<anon>") ]);
      isMeaningful = isMeaningfulName (aspect.name or "<anon>");
    in
    fx.bind (fx.effects.hasHandler "class") (
      hasClassHandler:
      fx.bind (if hasClassHandler then fx.send "class" null else fx.pure null) (
        targetClass:
        let
          classified = classifyKeys targetClass aspect;
          allClassKeys = classified.classKeys ++ classified.unregisteredClassKeys;
        in
        fx.bind (fx.seq (
          [ (emitClasses aspect allClassKeys nodeIdentity) (registerConstraints aspect) ]
          ++ map (emitNestedAspect aspect) classified.nestedKeys
        )) (_: resolveChildren aspect { inherit isMeaningful chainIdentity; })
      )
    );

  # --- Parametric resolution ---

  # Build the base attrset for a parametric resolution result.
  mkParametricBase =
    aspect: resolved:
    {
      inherit (aspect) name;
      meta =
        (aspect.meta or { })
        // (if builtins.isAttrs resolved then resolved.meta or { } else { })
        // { isParametric = true; fnArgNames = builtins.attrNames (aspect.__args or { }); };
    }
    // lib.optionalAttrs (aspect ? into) { inherit (aspect) into; }
    // lib.optionalAttrs (aspect ? provides) { inherit (aspect) provides; };

  # Merge the resolved value into the parametric base.
  mkParametricNext =
    aspect: base: resolved:
    if lib.isFunction resolved && !builtins.isAttrs resolved then
      if den.lib.aspects.isSubmoduleFn resolved then
        let
          merged = den.lib.aspects.types.aspectType.merge
            (aspect.meta.loc or [ (aspect.name or "<anon>") ])
            [ { file = aspect.meta.file or "<parametric>"; value = resolved; } ];
        in
        base // builtins.removeAttrs merged [ "meta" ]
      else
        base // { __fn = resolved; __args = lib.functionArgs resolved; }
    else
      base // builtins.removeAttrs resolved [ "meta" ];

  # Tag a parametric result with scope propagation and depth tracking.
  tagParametricResult =
    aspect: next:
    let
      parentScopeHandlers = aspect.__scopeHandlers or { };
      resolvedScopeHandlers = if builtins.isAttrs next then next.__scopeHandlers or { } else { };
      mergedScopeHandlers = parentScopeHandlers // resolvedScopeHandlers;
    in
    next
    // lib.optionalAttrs (mergedScopeHandlers != { }) { __scopeHandlers = mergedScopeHandlers; }
    // lib.optionalAttrs (aspect ? __ctxId) { inherit (aspect) __ctxId; }
    // { __parametricResolvedArgs = (aspect.__parametricResolvedArgs or [ ]) ++ builtins.attrNames (aspect.__args or { }); };

  maxParametricDepth = 10;

  # Prepare the fn for parametric resolution (scope injection + exactMatch handling).
  prepareParametricFn =
    aspect:
    let
      scopeHandlers = aspect.__scopeHandlers or null;
      scopeFn = if scopeHandlers != null then fx.effects.scope.provide scopeHandlers else null;
      rawFn = aspect.__fn;
      fn =
        if (aspect.meta.exactMatch or false) && scopeHandlers != null then
          args: rawFn (args // { __scopeKeys = builtins.attrNames scopeHandlers; })
        else
          rawFn;
      bound = fx.bind.fn (aspect.__args or { }) fn;
    in
    if scopeFn != null then scopeFn bound else bound;

  # Resolve a parametric aspect: bind fn, build result, tag, recurse.
  resolveParametric =
    aspect:
    let
      depth = aspect.__parametricDepth or 0;
    in
    if depth >= maxParametricDepth then
      throw "den: parametric resolution exceeded ${toString maxParametricDepth} levels for '${aspect.name or "<anon>"}'"
    else
      fx.bind (prepareParametricFn aspect) (
        resolved:
        let
          base = mkParametricBase aspect resolved;
          next = mkParametricNext aspect base resolved;
          tagged = tagParametricResult aspect next // { __parametricDepth = depth + 1; };
        in
        aspectToEffect tagged
      );

  # --- Top-level dispatch ---

  parametricInternalKeys = [ "__fn" "__args" "__parametricDepth" "__parametricResolvedArgs" ];

  aspectToEffect =
    aspect:
    if (aspect.__args or { }) != { } then
      resolveParametric aspect
    else
      compileStatic (builtins.removeAttrs aspect parametricInternalKeys);

in
{
  inherit
    aspectToEffect
    emitIncludes
    emitAspectPolicies
    structuralKeysSet
    wrapClassModule
    ctxFromHandlers
    ;
}
