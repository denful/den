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
    "traits"
    "classes"
    "__fn"
    "__args"
    "__functor"
    "__functionArgs"
    "__scopeHandlers"
    "__ctxId"
    "__parametricResolved"
    "_module"
    "_"
  ] (_: true);

  # Resolve collision policy from three levels: aspect meta → entity → global.
  # Shared by wrapClassModule (specialArgs collisions) and mkCollisionDetector
  # (_module.args collisions).
  resolveCollisionPolicy =
    {
      ctx,
      aspectPolicy,
      globalPolicy,
    }:
    name:
    if aspectPolicy != null then
      aspectPolicy
    else if
      builtins.isAttrs (ctx.${name} or null)
      && (ctx.${name} ? collisionPolicy)
      && ctx.${name}.collisionPolicy != null
    then
      ctx.${name}.collisionPolicy
    else
      globalPolicy;

  # Class modules (after aspectContentType unwrapping or from deferred
  # imports) may be { imports = [...]; } attrsets. The original function
  # is nested inside.  We recursively descend into imports to find and
  # wrap any functions that request den context args.
  wrapDeferredImports =
    args: imports:
    let
      go =
        imp:
        if builtins.isFunction imp then
          let
            result = wrapClassModule (args // { module = imp; });
          in
          {
            inherit (result) wrapped;
            value = result.module;
          }
        else if builtins.isAttrs imp && imp ? imports then
          let
            inner = map go imp.imports;
            anyWrapped = builtins.any (r: r.wrapped) inner;
          in
          {
            wrapped = anyWrapped;
            value = imp // {
              imports = map (r: r.value) inner;
            };
          }
        else
          {
            wrapped = false;
            value = imp;
          };
      results = map go imports;
      anyWrapped = builtins.any (r: r.wrapped) results;
    in
    {
      wrapped = anyWrapped;
      imports = map (r: r.value) results;
    };

  wrapClassModule =
    {
      module,
      ctx,
      aspectPolicy,
      globalPolicy,
    }:
    if builtins.isAttrs module && module ? imports then
      let
        result = wrapDeferredImports { inherit ctx aspectPolicy globalPolicy; } module.imports;
        policy = resolveCollisionPolicy { inherit ctx aspectPolicy globalPolicy; };
        denArgNames = builtins.attrNames ctx;
        advertisedArgs = lib.genAttrs denArgNames (_: true);
        validator =
          moduleArgs:
          let
            collisionChecks = lib.concatMap (
              name:
              let
                tryResult = builtins.tryEval (builtins.seq moduleArgs.${name} true);
                hasReal = tryResult.value or false;
                p = policy name;
              in
              if !hasReal then
                [ ]
              else if p == "error" then
                throw "den: class module arg '${name}' collides with module-system arg — set collisionPolicy to resolve"
              else if p == "class-wins" then
                [
                  "den: class module arg '${name}' collision — class-wins, den value dropped"
                ]
              else
                [
                  "den: class module arg '${name}' collision — den-wins, module-system value shadowed"
                ]
            ) denArgNames;
          in
          {
            warnings = collisionChecks;
          };
      in
      {
        module = module // {
          imports = result.imports;
        };
        inherit (result) wrapped;
      }
      // lib.optionalAttrs (result.wrapped && ctx != { }) {
        inherit validator advertisedArgs;
      }
    else if !builtins.isFunction module then
      {
        inherit module;
        wrapped = false;
      }
    else
      let
        allArgs = builtins.functionArgs module;
        argNames = builtins.attrNames allArgs;
        denArgNames = builtins.filter (k: ctx ? ${k}) argNames;
        # Only warn for args matching known schema kinds that have no default.
        # Avoids false warnings on module-system args (config, pkgs, etc.).
        schemaKinds = builtins.filter (
          n: n != "conf" && n != "classes" && n != "traits" && n != "aspect" && !(lib.hasPrefix "_" n)
        ) (builtins.attrNames (den.schema or { }));
        missingDenArgNames = builtins.filter (k: builtins.elem k schemaKinds && !(allArgs.${k} or false)) (
          builtins.filter (k: !(ctx ? ${k})) argNames
        );
        # Emit warnings for missing den args (matching schema kinds, no default)
        # regardless of whether other den args are found.
        warnedModule = builtins.foldl' (
          mod: k: lib.warn "den: class module requests '${k}' but no ${k} context is available" mod
        ) module missingDenArgNames;
      in
      if denArgNames == [ ] then
        {
          module = warnedModule;
          wrapped = false;
        }
      else
        let
          denArgs = lib.genAttrs denArgNames (k: ctx.${k});
          remainingArgs = removeAttrs allArgs denArgNames;
        in
        # Full application: all functionArgs are den args (no module-system args).
        # Call the function directly instead of wrapping — this handles the
        # { host }: ({ config, pkgs, ... }: {}) pattern where the outer function
        # returns another function (or any value) to be used as the class module.
        if remainingArgs == { } then
          {
            module = warnedModule denArgs;
            wrapped = true;
          }
        else
          let
            policy = resolveCollisionPolicy { inherit ctx aspectPolicy globalPolicy; };
            # G(X): the actual module wrapper. Merge order depends on policy.
            # For class-wins args, moduleArgs shadows denArgs (class value used).
            # For den-wins/error args, denArgs shadows moduleArgs (NixOS thunks
            # shadowed without evaluation).
            classWinsNames = builtins.filter (name: policy name == "class-wins") denArgNames;
            classWinsDen = lib.genAttrs classWinsNames (k: denArgs.${k});
            denWinsDen = removeAttrs denArgs classWinsNames;
            wrapper =
              moduleArgs:
              # class-wins args: den first, then moduleArgs shadows
              # den-wins/error args: moduleArgs first, then denArgs shadows
              warnedModule (classWinsDen // moduleArgs // denWinsDen);
            # Validate(X): collision detector. Receives same moduleArgs from
            # NixOS but only produces warnings/errors. The check is inside
            # the warnings value — a thunk that's only forced after the
            # module system's fixed point converges, avoiding recursion.
            validator =
              moduleArgs:
              let
                collisionChecks = lib.concatMap (
                  name:
                  let
                    # Only evaluates moduleArgs.${name} when config.warnings
                    # is consumed — after fixed point. tryEval catches the
                    # thunk failure when nobody set _module.args.${name}.
                    hasReal = (builtins.tryEval (builtins.seq moduleArgs.${name} true)).value or false;
                    p = policy name;
                  in
                  if !hasReal then
                    [ ]
                  else if p == "error" then
                    throw "den: class module arg '${name}' collides with module-system arg — set collisionPolicy to resolve"
                  else if p == "class-wins" then
                    [
                      "den: class module arg '${name}' collision — class-wins, den value dropped"
                    ]
                  else
                    [
                      "den: class module arg '${name}' collision — den-wins, module-system value shadowed"
                    ]
                ) denArgNames;
              in
              {
                warnings = collisionChecks;
              };
            # Both advertise den args as optional so NixOS passes thunks.
            advertisedArgs = remainingArgs // lib.genAttrs denArgNames (_: true);
          in
          {
            module = lib.setFunctionArgs wrapper advertisedArgs;
            # Validator emitted separately via emitClasses
            inherit validator advertisedArgs;
            wrapped = true;
          };

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
          module =
            if builtins.isAttrs rawValue && rawValue ? __contentValues then
              let
                vals = map (d: d.value) rawValue.__contentValues;
              in
              if builtins.length vals == 1 then builtins.head vals else { imports = vals; }
            else
              rawValue;
          result = wrapClassModule {
            inherit
              module
              ctx
              aspectPolicy
              globalPolicy
              ;
          };
          mainEmit = fx.send "emit-class" {
            class = k;
            identity = nodeIdentity;
            inherit (result) module;
            isContextDependent =
              result.wrapped || (aspect.__parametricResolved or false) || (aspect.meta.contextDependent or false);
          };
          validatorEmit = fx.send "emit-class" {
            class = k;
            identity = "${nodeIdentity}/<collision-validator>";
            module = lib.setFunctionArgs result.validator result.advertisedArgs;
            isContextDependent = true;
          };
        in
        [ mainEmit ] ++ lib.optional (result ? validator) validatorEmit
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
      ctx = ctxFromHandlers (aspect.__scopeHandlers or { });
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
                emitterCtx = ctxFromHandlers (aspect.__scopeHandlers or { });
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
    wrapClassModule
    ctxFromHandlers
    ;
}
