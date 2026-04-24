{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  identity = den.lib.aspects.fx.identity;
  inherit (den.lib.aspects.fx.handlers) constantHandler;
  inherit (den.lib.aspects) isParametricWrapper isMeaningfulName;

  structuralKeysSet = lib.genAttrs [
    "name"
    "description"
    "meta"
    "includes"
    "provides"
    "policies"
    "provide-to"
    "into"
    "__fn"
    "__args"
    "__functor"
    "__functionArgs"
    "__ctx"
    "__scopeHandlers"
    "__ctxId"
    "__parametricResolved"
    "_module"
    "_"
  ] (_: true);

  emitClasses =
    aspect: classKeys: nodeIdentity:
    fx.seq (
      map (
        k:
        fx.send "emit-class" {
          class = k;
          identity = nodeIdentity;
          module = aspect.${k};
          isContextDependent =
            (aspect.__parametricResolved or false) || (aspect.meta.contextDependent or false);
        }
      ) classKeys
    );

  registerConstraints =
    aspect:
    let
      rawHandleWith = aspect.meta.handleWith or null;
      rawExcludes = aspect.meta.excludes or [ ];
      handleWithList =
        if rawHandleWith == null then
          [ ]
        else if builtins.isList rawHandleWith then
          rawHandleWith
        else if builtins.isAttrs rawHandleWith then
          [ rawHandleWith ]
        else
          [ ];
      excludeList = map (ref: {
        type = "exclude";
        scope = "subtree";
        identity = identity.pathKey (identity.aspectPath ref);
      }) rawExcludes;
      allConstraints = handleWithList ++ excludeList;
      owner = aspect.name or "<anon>";
    in
    fx.seq (map (c: fx.send "register-constraint" (c // { inherit owner; })) allConstraints);

  # Fold includes through emit-include effects, tagging each with its
  # positional index and parent __scopeHandlers so the handler
  # can derive stable identities and propagate context to children.
  emitIncludes =
    {
      __parentScopeHandlers ? null,
      __parentCtxId ? null,
    }:
    incs:
    let
      len = builtins.length incs;
      go =
        idx: acc:
        if idx >= len then
          acc
        else
          go (idx + 1) (
            fx.bind acc (
              results:
              fx.bind (fx.send "emit-include" (
                {
                  child = builtins.elemAt incs idx;
                  inherit idx;
                }
                // lib.optionalAttrs (__parentScopeHandlers != null) { inherit __parentScopeHandlers; }
                // lib.optionalAttrs (__parentCtxId != null) { inherit __parentCtxId; }
              )) (childResults: fx.pure (results ++ childResults))
            )
          );
    in
    go 0 (fx.pure [ ]);

  emitTransitions =
    aspect:
    let
      # meta.into survives freeform deferredModule; aspect.into is the fallback.
      intoFn = aspect.meta.into or aspect.into or null;
      hasManualInto = intoFn != null && lib.isFunction intoFn;
      # Only fire per-policy dispatch for stage roots (aspects with __ctxStage).
      # Inner provides/includes share the stage name but are not transition points.
      isStageRoot = aspect ? __ctxStage;
      hasPolicies =
        isStageRoot && den.lib.aspects.fx.handlers.policyEffectNamesFor (aspect.name or "") != [ ];
    in
    if hasManualInto || hasPolicies then
      fx.send "into-transition" {
        intoFn = if hasManualInto then intoFn else null;
        self = aspect;
      }
    else
      fx.pure [ ];

  mkPositionalInclude =
    {
      innerFn,
      ctx,
      name,
      scopeHandlers,
      aspect,
      providerMeta,
    }:
    let
      resolved = innerFn ctx;
      resolvedArgs = if lib.isFunction resolved then lib.functionArgs resolved else { };
    in
    if lib.isFunction resolved && !builtins.isAttrs resolved then
      {
        inherit name;
        meta = providerMeta;
        __fn = resolved;
        __args = resolvedArgs;
      }
      // lib.optionalAttrs (scopeHandlers != null) { __parentScopeHandlers = scopeHandlers; }
      // lib.optionalAttrs (aspect ? __ctxId) { __parentCtxId = aspect.__ctxId; }
    else
      (if builtins.isAttrs resolved then resolved else { })
      // {
        inherit name;
        meta = providerMeta;
        includes = (if builtins.isAttrs resolved then resolved.includes or [ ] else [ ]);
      }
      // lib.optionalAttrs (aspect ? __ctxId) { __ctxId = aspect.__ctxId; };

  mkNamedInclude =
    {
      innerFn,
      providerVal,
      isParamWrapper,
      name,
      scopeHandlers,
      aspect,
      providerMeta,
      providerArgs,
    }:
    {
      inherit name;
      meta =
        providerMeta
        // (
          if isParamWrapper then
            builtins.removeAttrs (providerVal.meta or { }) [
              "provider"
              "selfProvide"
            ]
          else
            { }
        );
      __fn = if lib.isFunction innerFn then innerFn else _: providerVal;
      __args = providerArgs;
    }
    // lib.optionalAttrs (scopeHandlers != null) { __parentScopeHandlers = scopeHandlers; }
    // lib.optionalAttrs (aspect ? __ctxId) { __parentCtxId = aspect.__ctxId; };

  emitSelfProvide =
    aspect:
    let
      name = aspect.name or "<anon>";
      provides = aspect.provides or { };
      providerVal = provides.${name};
      scopeHandlers = aspect.__scopeHandlers or null;
      ctx = aspect.__ctx or { };
      isParamWrapper = isParametricWrapper providerVal;
      innerFn =
        if isParamWrapper then
          providerVal.__fn
        else if builtins.isAttrs providerVal && providerVal ? __fn then
          providerVal.__fn
        else if builtins.isAttrs providerVal && lib.isFunction providerVal then
          providerVal.__functor providerVal
        else
          providerVal;
      providerArgs =
        if isParamWrapper then
          providerVal.__args
        else if lib.isFunction innerFn then
          lib.functionArgs innerFn
        else
          { };
    in
    if provides ? ${name} then
      let
        isPositionalFn = lib.isFunction innerFn && providerArgs == { };
        providerMeta = {
          provider = (aspect.meta.provider or [ ]) ++ [ name ];
          selfProvide = true;
        };
        shared = {
          inherit
            innerFn
            name
            scopeHandlers
            aspect
            providerMeta
            ;
        };
        include =
          if isPositionalFn then
            mkPositionalInclude (shared // { inherit ctx; })
          else
            mkNamedInclude (shared // { inherit providerVal isParamWrapper providerArgs; });
      in
      fx.send "emit-include" include
    else
      fx.pure [ ];

  chainWrap =
    aspect: nodeIdentity: isMeaningful: comp:
    if isMeaningful then
      fx.bind (fx.send "chain-push" {
        identity = nodeIdentity;
        stage = aspect.__ctxStage or null;
      }) (_: fx.bind comp (result: fx.bind (fx.send "chain-pop" null) (_: fx.pure result)))
    else
      comp;

  resolveChildren =
    aspect:
    { isMeaningful, chainIdentity }:
    let
      scopeHandlers = aspect.__scopeHandlers or null;
      ctxId = aspect.__ctxId or null;
      # Emit provide-to effects for cross-entity data routing.
      # Aspects declare provide-to.${label} = data; the handler collects
      # emissions in state.provideTo for phase 2 distribution.
      provideToData = aspect."provide-to" or { };
      emitProvideTo =
        if provideToData == { } then
          fx.pure null
        else
          fx.seq (
            map (
              label:
              fx.send "provide-to" {
                inherit label;
                content = provideToData.${label};
                emitterCtx = aspect.__ctx or { };
                aspectName = aspect.name or "<anon>";
                targetEntity = null;
              }
            ) (builtins.attrNames provideToData)
          );
      childResolution = fx.bind (emitSelfProvide aspect) (
        selfProvResults:
        fx.bind emitProvideTo (
          _:
          fx.bind (emitTransitions aspect) (
            transitionResults:
            fx.bind (emitIncludes {
              __parentScopeHandlers = scopeHandlers;
              __parentCtxId = ctxId;
            } (aspect.includes or [ ])) (children: fx.pure (selfProvResults ++ transitionResults ++ children))
          )
        )
      );
    in
    fx.bind (chainWrap aspect chainIdentity isMeaningful childResolution) (
      allChildren:
      let
        resolved = aspect // {
          includes = allChildren;
        };
      in
      fx.bind (fx.send "resolve-complete" resolved) (_: fx.pure resolved)
    );

  compileStatic =
    aspect:
    let
      nodeIdentity = identity.pathKey (identity.aspectPath aspect);
      # Chain identity strips ctxId — the chain tracks includes provenance,
      # not fan-out dedup. This keeps chain entries aligned with entry
      # fullNames (provider/name) so parent resolution in graph.nix works.
      chainIdentity = identity.pathKey ((aspect.meta.provider or [ ]) ++ [ (aspect.name or "<anon>") ]);
      classKeys = builtins.filter (k: !(structuralKeysSet ? ${k})) (builtins.attrNames aspect);
      rawName = aspect.name or "<anon>";
      isMeaningful = isMeaningfulName rawName;
    in
    fx.bind (fx.seq [
      (emitClasses aspect classKeys nodeIdentity)
      (registerConstraints aspect)
    ]) (_: resolveChildren aspect { inherit isMeaningful chainIdentity; });

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
      __parametricResolved = true;
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
              meta = (aspect.meta or { }) // (if builtins.isAttrs resolved then resolved.meta or { } else { });
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
        ]
      );

in
{
  inherit
    aspectToEffect
    emitIncludes
    emitTransitions
    emitSelfProvide
    structuralKeysSet
    ;
}
