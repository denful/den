{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  handlers = den.lib.aspects.fx.handlers;
  identity = den.lib.aspects.fx.identity;
  inherit (den.lib.aspects.fx.aspect) aspectToEffect drainDeadLettersHandler;

  # Compose two handler sets, chaining handlers for shared effect names.
  # For overlapping keys: b's resume wins, a's state wins (a runs on b's output state).
  #
  # IMPORTANT LIMITATIONS:
  # 1. Composed handlers MUST NOT write to the same state keys — a runs on b's output
  #    state so shared keys would double-append.
  # 2. When b returns an effectful resume (computation), the sub-computation runs with
  #    b's state, not a's. State changes from a are lost for the duration of the
  #    sub-computation. For shared effects, b MUST return plain values (not computations)
  #    as resume, or a's state mutations will be discarded.
  #
  # Designed for the tracing use case: tracingHandler (b) controls resume,
  # defaultHandlers (a) accumulates paths/imports. Both constraints hold for this case.
  composeHandlers =
    a: b:
    let
      shared = builtins.intersectAttrs a b;
      sharedComposed = builtins.mapAttrs (
        name: _:
        { param, state }:
        let
          rb = b.${name} { inherit param state; };
          ra = a.${name} {
            inherit param;
            state = rb.state;
          };
        in
        {
          resume = rb.resume;
          state = ra.state;
        }
      ) shared;
    in
    a // b // sharedComposed;

  # Each handler set MUST handle disjoint effect names — `//` merge is
  # last-wins, so overlap silently shadows. constantHandler generates
  # dynamic keys from ctx (host, user, class, etc.) which don't collide
  # with the named handlers below.
  #
  # Priority (low→high, last wins via //):
  # 1. traitArgHandler — trait names as effects for parametric consumers
  # 2. constantHandler — den context args; overwrites trait names on collision
  # 3. Named handlers — emit-trait, emit-class, chain-*, etc. (no collision)
  # 4. state.handler — always last
  defaultHandlers =
    { class, ctx }:
    let
      # Top-level den.traits lives outside den.schema, breaking
      # the evaluation cycle that existed with den.schema.traits.
      traitSchemas = den.traits or { };
    in
    handlers.traitArgHandler traitSchemas
    // handlers.constantHandler (
      {
        inherit class;
        "aspect-chain" = [ ];
      }
      // ctx
    )
    // handlers.traitCollectorHandler { inherit ctx traitSchemas; }
    // handlers.classCollectorHandler
    // handlers.constraintRegistryHandler
    // handlers.chainHandler
    // handlers.includeHandler
    // handlers.transitionHandler
    // handlers.ctxSeenHandler
    // identity.pathSetHandler
    // identity.collectPathsHandler
    // handlers.registerAspectPolicyHandler
    // handlers.dispatchPolicyIncludesHandler
    // handlers.deferredIncludeHandler
    // handlers.drainDeferredHandler
    // handlers.deadLetterHandler
    // drainDeadLettersHandler
    // resolveEntityHandler
    // handlers.forwardHandler
    // handlers.provideToHandler
    // fx.effects.state.handler;

  # resolve-entity resolves an entity by kind using resolveEntity.
  # Always returns a valid entity — existence gating removed.
  # Strips den.default from child entity includes to prevent
  # cross-context duplicate resolution: den.default is resolved once
  # at the root entity level; child entities resolved during transitions
  # must not re-resolve it in a different context (which would produce
  # duplicate NixOS module definitions).
  # Note: filter uses pointer identity — den.default in schemaIncludes
  # is the same fixpoint value as denDefault here (no normalization).
  denDefault = den.default or null;
  resolveEntityHandler = {
    "resolve-entity" =
      { param, state }:
      let
        kind = param.kind;
        currentCtx = (state.currentCtx or (_: { })) null;
        entity = den.lib.resolveEntity kind currentCtx;
        strippedIncludes =
          if denDefault != null then
            builtins.filter (inc: inc != denDefault) entity.includes
          else
            entity.includes;
      in
      {
        resume = entity // {
          includes = strippedIncludes;
        };
        inherit state;
      };
  };

  # IMPLEMENTATION DETAIL: Fields wrapped as thunks (`_: value`) survive
  # builtins.deepSeq — the trampoline deepSeqs state at each step, but
  # deepSeq on a function forces the closure, not its application. This
  # prevents re-materializing large attrsets (pathSet, seen, etc.) at
  # every trampoline step. Unwrap with `state.field null`.
  #
  # Plain fields (class, transitionDepth, etc.) are small and safe to
  # deepSeq directly.
  defaultState = {
    seen = _: { };
    classImports = _: { };
    constraintRegistry = _: { };
    constraintFilters = _: [ ];
    pathSet = _: { };
    includesChain = _: [ ];
    deferredIncludes = _: [ ];
    provideTo = _: [ ];
    traits = _: { };
    deferredTraits = _: { };
    consumedTraits = _: { };
    aspectPolicies = _: { };
    forwardSpecs = _: [ ];
    deadLetterQueue = _: [ ];
  };

  mkPipeline =
    {
      extraHandlers ? { },
      extraState ? { },
      class,
    }:
    {
      self,
      ctx,
    }:
    let
      bootstrapAndResolve = aspectToEffect self;

      rootHandlers = defaultHandlers {
        inherit class;
        ctx = ctx // {
          "aspect-chain" = [ self ];
        };
      };
    in
    fx.handle {
      handlers = composeHandlers rootHandlers extraHandlers;
      # Wrap currentCtx in a thunk so deepSeq doesn't force NixOS config objects.
      state =
        defaultState
        // extraState
        // {
          currentCtx = _: ctx;
          inherit class;
        };
    } bootstrapAndResolve;

  # Returns raw fx.handle result with { value, state }.
  fxFullResolve =
    {
      class,
      self,
      ctx,
      extraState ? { },
    }:
    mkPipeline { inherit class extraState; } { inherit self ctx; };

  inherit (den.lib.aspects) normalizeRoot;

  # Forward post-processing: for each registered forward spec, resolve the
  # source aspect via sub-pipeline, wrap results via buildForwardAspect, and
  # merge into the target class bucket.
  #
  # collectClassMods recursively extracts all intoClass modules from a
  # forward aspect and its includes (mkAdapterAspect nests a companion
  # mkDirectAspect in includes).
  collectClassMods =
    cls: aspect:
    let
      own = if aspect ? ${cls} then [ aspect.${cls} ] else [ ];
      nested = builtins.concatMap (collectClassMods cls) (aspect.includes or [ ]);
    in
    own ++ nested;

  # Returns { classImports, provideTo } with forwarded content merged.
  applyForwardSpecs =
    forwardSpecs: classImports:
    builtins.foldl'
      (
        acc: spec:
        let
          normalizedSource = normalizeRoot spec.sourceAspect;
          sub = runSubPipeline {
            class = spec.fromClass;
            self = normalizedSource;
            ctx = spec.__resolveCtx;
            extraState = {
              aspectPolicies = spec.__aspectPolicies;
            };
          };
          rawSourceModule = {
            imports = sub.classImports.${spec.fromClass} or [ ];
          };
          sourceModule = spec.mapModule rawSourceModule;
          forwardAspect = handlers.buildForwardAspect spec sourceModule;
          newMods = collectClassMods spec.intoClass forwardAspect;
        in
        {
          classImports = acc.classImports // {
            ${spec.intoClass} = (acc.classImports.${spec.intoClass} or [ ]) ++ newMods;
          };
          provideTo = acc.provideTo ++ sub.provideTo;
        }
      )
      {
        inherit classImports;
        provideTo = [ ];
      }
      forwardSpecs;

  # Thin wrapper: runs sub-pipeline, materializes state thunks.
  # Each call site does its own post-processing.
  runSubPipeline =
    {
      class,
      self,
      ctx,
      extraState ? { },
    }:
    let
      result = fxFullResolve {
        inherit
          class
          self
          ctx
          extraState
          ;
      };
    in
    let
      rawClassImports = result.state.classImports null;
      forwardSpecs = result.state.forwardSpecs null;
      forwarded = applyForwardSpecs forwardSpecs rawClassImports;
      finalCtx = (result.state.currentCtx or (_: { })) null;
      wrappedClassImports = wrapCollectedClasses finalCtx forwarded.classImports;
      pipelineProvideTo = (result.state.provideTo or (_: [ ])) null;
    in
    {
      classImports = wrappedClassImports;
      traits = result.state.traits null;
      provideTo = pipelineProvideTo ++ forwarded.provideTo;
    };

  # Post-pipeline wrapping pass: wrap raw class entries (__rawEntry = true)
  # using wrapClassModule with the full enriched context they carry.
  # Non-raw entries pass through unchanged.
  wrapCollectedClasses =
    enrichedCtx: classImports:
    lib.mapAttrs (
      class: entries:
      lib.concatMap (
        entry:
        if !(entry.__rawEntry or false) then
          # Legacy or already-wrapped entry — pass through
          [ entry ]
        else
          let
            # Merge enrichment-only keys into the entry's emit-time ctx.
            # Only keys NOT already in entry.ctx are added — this avoids
            # overwriting entity bindings (host, user) from a different
            # scope while providing enrichment args (isNixos, isDarwin).
            enrichmentKeys = lib.filterAttrs (k: _: !(entry.ctx ? ${k})) enrichedCtx;
            ctx = entry.ctx // enrichmentKeys;
            result = den.lib.aspects.fx.aspect.wrapClassModule {
              inherit ctx;
              inherit (entry)
                module
                aspectPolicy
                globalPolicy
                traitNames
                ;
            };
            # Enrichment-only args must NOT be advertised to NixOS — they
            # don't exist in _module.args and would trigger infinite recursion
            # when NixOS tries to look them up. Standard den args (host, user)
            # DO exist in _module.args and are safe to advertise.
            enrichmentOnlyKeys = builtins.attrNames enrichmentKeys;
            # Strip enrichment-only keys from the wrapped module's advertised
            # args so NixOS won't try to resolve them from _module.args.
            # For wrapped function modules, strip enrichment-only keys from
            # the advertised args. setFunctionArgs returns an attrset with
            # __functor + __functionArgs, so check __functionArgs presence.
            # Strip args that NixOS can't resolve from the module's advertised
            # functionArgs.  Without this, NixOS tries _module.args.${name} for
            # every advertised arg and crashes when the key doesn't exist —
            # even when the arg has a default in the Nix function.
            #
            # For wrapped modules: enrichment-only keys were injected by den
            # and don't exist in _module.args.
            # For unwrapped modules: any arg with a default that isn't in ctx
            # and isn't a standard module-system arg should be hidden so NixOS
            # uses the function's native default instead of probing _module.args.
            # Strip args that NixOS can't resolve from the module's advertised
            # functionArgs.  Without this, NixOS tries _module.args.${name} for
            # every advertised arg and crashes when the key doesn't exist —
            # even when the arg has a default in the Nix function.
            #
            # For wrapped modules (setFunctionArgs attrset): enrichment-only
            # keys were injected by den and don't exist in _module.args.
            # For unwrapped raw functions: any arg with a default that isn't
            # in ctx should be hidden so NixOS uses the function's native
            # default instead of probing _module.args.
            isWrappedAttrset = builtins.isAttrs result.module && result.module ? __functionArgs;
            rawFuncArgs =
              if isWrappedAttrset then
                result.module.__functionArgs
              else if builtins.isFunction result.module then
                builtins.functionArgs result.module
              else
                { };
            argsToStrip =
              if result.wrapped then
                enrichmentOnlyKeys
              else
                # For unwrapped modules, strip args with defaults that aren't
                # in ctx (they're unknown to both den and NixOS).
                builtins.filter (k: rawFuncArgs.${k} or false && !(ctx ? ${k})) (builtins.attrNames rawFuncArgs);
            isFunction = builtins.isFunction result.module;
            finalModule =
              if argsToStrip == [ ] || (!isWrappedAttrset && !isFunction) then
                result.module
              else if isWrappedAttrset then
                result.module // { __functionArgs = removeAttrs rawFuncArgs argsToStrip; }
              else
                lib.setFunctionArgs result.module (removeAttrs rawFuncArgs argsToStrip);
            nodeIdentity = entry.identity or "<anon>";
            isAnon =
              !(den.lib.aspects.isMeaningfulName nodeIdentity)
              || lib.hasPrefix "<root>/" nodeIdentity
              || lib.hasInfix "/<anon>:" nodeIdentity;
            isContextDependent = result.wrapped || (entry.isContextDependent or false);
            finalIdentity =
              if isContextDependent then nodeIdentity else lib.head (lib.splitString "/{" nodeIdentity);
            finalLoc = "${class}@${finalIdentity}";
            wrappedMod =
              if isAnon then
                lib.setDefaultModuleLocation finalLoc finalModule
              else
                {
                  key = finalLoc;
                  _file = finalLoc;
                  imports = [ finalModule ];
                };
            validatorMod =
              let
                validatorLoc = "${class}@${nodeIdentity}/<collision-validator>";
                validatorModule = lib.setFunctionArgs result.validator (
                  result.validatorAdvertisedArgs or result.advertisedArgs or { }
                );
              in
              lib.setDefaultModuleLocation validatorLoc validatorModule;
          in
          if result.unsatisfied or false then
            builtins.trace
              "den: class module ${class}@${nodeIdentity} skipped — context never provided: ${toString result.missingArgs}"
              [ ]
          else
            [ wrappedMod ] ++ lib.optional (result ? validator) validatorMod
      ) entries
    ) classImports;

  # Drop-in resolve shape: returns { imports = [...] }.
  fxResolve =
    {
      class,
      self,
      ctx,
      crossEntityTraits ? { },
    }:
    let
      result = mkPipeline { inherit class; } { inherit self ctx; };
      traitSchemas = den.traits or { };
      traits = result.state.traits null;
      deferredTraits = result.state.deferredTraits null;
      consumedTraits = (result.state.consumedTraits or (_: { })) null;

      # partialOk validation: error when trait consumed at pipeline time
      # AND has deferred emissions, unless schema says partialOk = true.
      partialOkViolations = builtins.filter (
        traitName:
        consumedTraits ? ${traitName}
        && (deferredTraits.${traitName} or [ ]) != [ ]
        && !(traitSchemas.${traitName}.partialOk or false)
      ) (builtins.attrNames consumedTraits);

      # Synthetic module injecting _den.traits into evalModules fixpoint.
      # Only added when trait schemas exist — zero overhead otherwise.
      traitModule =
        {
          config,
          lib,
          pkgs,
          options,
          modulesPath,
          ...
        }@moduleArgs:
        {
          options._den.traits = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
            internal = true;
          };
          config._den.traits = lib.mapAttrs (
            traitName: schema:
            let
              strategy = schema.collection or "list";
              raw = traits.${traitName} or (if strategy == "map" then { } else [ ]);
              deferred = deferredTraits.${traitName} or [ ];
              deferredData = map (e: e.value moduleArgs) deferred;
              crossEntity = crossEntityTraits.${traitName} or (if strategy == "map" then { } else [ ]);
              mergeMaps =
                base: extras:
                builtins.foldl' (
                  acc: d:
                  let
                    dupes = builtins.filter (k: acc ? ${k}) (builtins.attrNames d);
                  in
                  if dupes != [ ] then
                    throw "den: trait '${traitName}' map collection: duplicate key '${builtins.head dupes}'"
                  else
                    acc // d
                ) base extras;
            in
            if strategy == "map" then
              # "map": merge pipeline data, deferred emissions, and cross-entity data
              # (duplicates error across all three)
              mergeMaps raw (deferredData ++ [ crossEntity ])
            else
              # "list": pipeline data, deferred emissions, then cross-entity data
              raw ++ deferredData ++ crossEntity
          ) traitSchemas;
        };

      hasTraitSchemas = traitSchemas != { };
    in
    if partialOkViolations != [ ] then
      throw "den: traits consumed at pipeline time have deferred (Tier 3) emissions without partialOk: ${builtins.concatStringsSep ", " partialOkViolations}. Set partialOk = true in the trait schema to allow partial pipeline-time data."
    else
      let
        rawClassImports = result.state.classImports null;
        forwardSpecs = result.state.forwardSpecs null;
        # forwarded.provideTo intentionally ignored — fxResolve never
        # exposed provideTo (only returns { imports }). provideTo from
        # forward sub-pipelines is handled by runSubPipeline callers.
        forwarded = applyForwardSpecs forwardSpecs rawClassImports;
        # Extract enriched context from pipeline state for post-pipeline wrapping.
        # Enrichment policies inject non-schema bindings (isNixos, isDarwin, etc.)
        # that may not have been available at class module emit time.
        finalCtx = (result.state.currentCtx or (_: { })) null;
        wrappedClassImports = wrapCollectedClasses finalCtx forwarded.classImports;
        # Dead letter queue diagnostics — warn about keys never claimed by any registry.
        finalDLQ = (result.state.deadLetterQueue or (_: [ ])) null;
        _dlqWarn = builtins.seq (map (
          entry:
          builtins.trace "den: dead letter — key '${entry.key}' from aspect '${entry.aspectName}' never matched a registered class or trait" null
        ) finalDLQ) null;
      in
      builtins.seq _dlqWarn {
        # Target class imports only — multi-class data accessible via
        # fxFullResolve (state.classImports null). Not exposed here because
        # fxResolve's return is used as a NixOS deferredModule by entity
        # types — extra attrs would error.
        imports = (wrappedClassImports.${class} or [ ]) ++ lib.optional hasTraitSchemas traitModule;
      };
in
{
  inherit
    composeHandlers
    defaultHandlers
    defaultState
    mkPipeline
    fxFullResolve
    runSubPipeline
    fxResolve
    ;
}
