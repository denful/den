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

  # Reconstruct ctx from scope handlers. constantHandler maps each key
  # to { param, state }: { resume = value; inherit state; }, so invoking
  # with dummy args extracts the original value. This works for all
  # aspects in the tree (not just stage roots) since __scopeHandlers
  # propagates to children, unlike __ctx which only exists on roots.
  ctxFromHandlers =
    handlers:
    lib.mapAttrs (
      _: handler:
      (handler {
        param = null;
        state = { };
      }).resume
    ) handlers;

  inherit (import ./include-emit.nix { inherit lib den; } { inherit ctxFromHandlers; })
    emitIncludes
    emitAspectPolicies
    registerConstraints
    ;

  emitClasses =
    aspect: classKeys: nodeIdentity:
    let
      ctx = ctxFromHandlers (aspect.__scopeHandlers or { });
      aspectPolicy = aspect.meta.collisionPolicy or null;
      globalPolicy = den.config.classModuleCollisionPolicy or "error";
    in
    fx.seq (
      lib.concatMap (
        k:
        let
          rawValue = aspect.${k};
          # aspectContentType wraps values with __contentValues/__provider.
          # Unwrap to recover the original module value for wrapClassModule.
          # Lists are coerced to per-element processing; bare values become singletons.
          modules = den.lib.aspects.fx.contentUtil.unwrapContentValuesList rawValue;
          # Process each module element independently.
          indexed = lib.imap0 (idx: module: { inherit idx module; }) modules;
          isMulti = builtins.length modules > 1;
        in
        lib.concatMap (
          { idx, module }:
          let
            elemIdentity = if isMulti then "${nodeIdentity}[${toString idx}]" else nodeIdentity;
          in
          [
            (fx.send "emit-class" {
              class = k;
              identity = elemIdentity;
              inherit
                module
                ctx
                aspectPolicy
                globalPolicy
                ;
              __rawEntry = true;
              isContextDependent =
                let
                  resolvedArgs = aspect.__parametricResolvedArgs or [ ];
                  usesCtxArgs = resolvedArgs != [ ] && builtins.any (ak: ctx ? ${ak}) resolvedArgs;
                in
                usesCtxArgs || (aspect.meta.contextDependent or false);
            })
          ]
        ) indexed
      ) classKeys
    );

  installPolicies =
    (import ./policy-dispatch.nix { inherit lib den; } { inherit aspectToEffect ctxFromHandlers; })
    .installPolicies;

  chainWrap =
    nodeIdentity: isMeaningful: comp:
    if isMeaningful then
      fx.bind (fx.send "chain-push" {
        identity = nodeIdentity;
      }) (_: fx.bind comp (result: fx.bind (fx.send "chain-pop" null) (_: fx.pure result)))
    else
      comp;

  resolveChildren =
    aspect:
    { isMeaningful, chainIdentity }:
    let
      scopeHandlers = aspect.__scopeHandlers or null;
      ctxId = aspect.__ctxId or null;
      emitCtx = {
        __parentScopeHandlers = scopeHandlers;
        __parentCtxId = ctxId;
      };
      # Includes resolve before policy dispatch so deferred parametric
      # includes drain when context widens during entity resolution.
      childResolution = fx.bind (emitAspectPolicies aspect) (
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
    in
    fx.bind (chainWrap chainIdentity isMeaningful childResolution) (
      allChildren:
      let
        resolved = aspect // {
          includes = allChildren;
        };
      in
      fx.bind (fx.send "resolve-complete" resolved) (_: fx.pure resolved)
    );

  # Build a nested sub-aspect from a freeform key and recurse via aspectToEffect.
  emitNestedAspect =
    aspect: k:
    let
      rawValue = aspect.${k};
      innerValue = den.lib.aspects.fx.contentUtil.unwrapContentValuesRaw rawValue;
      subAspect =
        (if builtins.isAttrs innerValue then innerValue else { })
        // {
          name = k;
          meta = (aspect.meta or { }) // {
            provider = (aspect.meta.provider or [ ]) ++ [ (aspect.name or "<anon>") ];
          };
        }
        // lib.optionalAttrs (aspect ? __scopeHandlers) {
          inherit (aspect) __scopeHandlers;
        }
        // lib.optionalAttrs (aspect ? __ctxId) {
          inherit (aspect) __ctxId;
        };
    in
    aspectToEffect subAspect;

  compileStatic =
    aspect:
    let
      nodeIdentity = identity.key aspect;
      # Chain identity strips ctxId — the chain tracks includes provenance,
      # not fan-out dedup. This keeps chain entries aligned with entry
      # fullNames (provider/name) so parent resolution in graph.nix works.
      chainIdentity = identity.pathKey ((aspect.meta.provider or [ ]) ++ [ (aspect.name or "<anon>") ]);
      rawName = aspect.name or "<anon>";
      isMeaningful = isMeaningfulName rawName;
    in
    fx.bind (fx.effects.hasHandler "class") (
      hasClassHandler:
      fx.bind (if hasClassHandler then fx.send "class" null else fx.pure null) (
        targetClass:
        let
          classified = classifyKeys targetClass aspect;
          inherit (classified)
            classKeys
            nestedKeys
            unregisteredClassKeys
            ;
          allClassKeys = classKeys ++ unregisteredClassKeys;
        in
        fx.bind (fx.seq (
          [
            (emitClasses aspect allClassKeys nodeIdentity)
            (registerConstraints aspect)
          ]
          ++ map (k: emitNestedAspect aspect k) nestedKeys
        )) (_: resolveChildren aspect { inherit isMeaningful chainIdentity; })
      )
    );

  # Submodule functions merge through the type system; bare functions
  # become another parametric level; attrsets merge directly.
  mkParametricNext =
    aspect: base: resolved:
    let
      inherit (den.lib.aspects) isSubmoduleFn;
      isResolvedSubmoduleFn =
        lib.isFunction resolved && !builtins.isAttrs resolved && isSubmoduleFn resolved;
    in
    if lib.isFunction resolved && !builtins.isAttrs resolved then
      if isResolvedSubmoduleFn then
        let
          merged = den.lib.aspects.types.aspectType.merge (aspect.meta.loc or [ (aspect.name or "<anon>") ]) [
            {
              file = aspect.meta.file or "<parametric>";
              value = resolved;
            }
          ];
        in
        base // builtins.removeAttrs merged [ "meta" ]
      else
        base
        // {
          __fn = resolved;
          __args = lib.functionArgs resolved;
        }
    else
      base // builtins.removeAttrs resolved [ "meta" ];

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
    // {
      __parametricResolvedArgs =
        (aspect.__parametricResolvedArgs or [ ]) ++ builtins.attrNames (aspect.__args or { });
    };

  maxParametricDepth = 10;

  # Two cases:
  # 1. __args has named args → parametric. Resolve via bind.fn, compile result.
  # 2. Otherwise → static. Strip __fn/__args, compile the attrset directly.
  aspectToEffect =
    aspect:
    let
      userArgs = aspect.__args or { };
      isParametric = userArgs != { };
      depth = aspect.__parametricDepth or 0;
      scopeHandlers = aspect.__scopeHandlers or null;
      scopeFn = if scopeHandlers != null then fx.effects.scope.provide scopeHandlers else null;
    in
    if isParametric then
      if depth >= maxParametricDepth then
        throw "den: parametric resolution exceeded ${toString maxParametricDepth} levels for '${aspect.name or "<anon>"}' — likely a curried function that never bottoms out"
      else
        let
          rawFn = aspect.__fn;
          fn =
            if (aspect.meta.exactMatch or false) && scopeHandlers != null then
              args: rawFn (args // { __scopeKeys = builtins.attrNames scopeHandlers; })
            else
              rawFn;
          resolveFn = if scopeFn != null then scopeFn (fx.bind.fn userArgs fn) else fx.bind.fn userArgs fn;
        in
        fx.bind resolveFn (
          resolved:
          let
            base = {
              inherit (aspect) name;
              meta =
                (aspect.meta or { })
                // (if builtins.isAttrs resolved then resolved.meta or { } else { })
                // {
                  isParametric = true;
                  fnArgNames = builtins.attrNames userArgs;
                };
            }
            // lib.optionalAttrs (aspect ? into) { inherit (aspect) into; }
            // lib.optionalAttrs (aspect ? provides) { inherit (aspect) provides; };
            next = mkParametricNext aspect base resolved;
            tagged = tagParametricResult aspect next // {
              __parametricDepth = depth + 1;
            };
          in
          aspectToEffect tagged
        )
    else
      compileStatic (
        builtins.removeAttrs aspect [
          "__fn"
          "__args"
          "__parametricDepth"
          "__parametricResolvedArgs"
        ]
      );

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
