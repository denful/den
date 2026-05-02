{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  handlers = den.lib.aspects.fx.handlers;
  identity = den.lib.aspects.fx.identity;
  inherit (den.lib.aspects.fx.aspect) aspectToEffect;
  route = import ./route.nix { inherit lib den; };

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
  # 1. constantHandler — den context args
  # 2. Named handlers — emit-class, chain-*, etc. (no collision)
  # 3. state.handler — always last
  defaultHandlers =
    { class, ctx }:
    handlers.constantHandler (
      {
        inherit class;
        "aspect-chain" = [ ];
      }
      // ctx
    )
    // handlers.classCollectorHandler
    // handlers.constraintRegistryHandler
    // handlers.chainHandler
    // handlers.includeHandler
    // handlers.ctxSeenHandler
    // identity.pathSetHandler
    // identity.collectPathsHandler
    // handlers.registerAspectPolicyHandler
    // handlers.deferredIncludeHandler
    // handlers.drainDeferredHandler
    // handlers.registerRouteHandler
    // handlers.registerInstantiateHandler
    // handlers.provideHandler
    // resolveEntityHandler
    // handlers.forwardHandler
    // fx.effects.state.handler;

  # resolve-entity resolves an entity by kind using resolveEntity.
  # Strips den.default from child entity includes to prevent
  # cross-context duplicate resolution: den.default is resolved once
  # at the root entity level; child entities must not re-resolve it
  # in a different context (which would produce duplicate NixOS
  # module definitions). Filter uses pointer identity.
  denDefault = den.default or null;
  resolveEntityHandler = {
    "resolve-entity" =
      { param, state }:
      let
        kind = param.kind;
        scope = state.currentScope;
        currentCtx = if scope == null then { } else (state.scopeContexts null).${scope} or { };
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
  # Plain fields (class, currentScope, etc.) are small and safe to
  # deepSeq directly.

  # mkScopeId: injective scope identity from a context attrset.
  # Produces a canonical comma-separated "key=value" string, sorted by key.
  mkScopeId =
    ctx:
    lib.concatStringsSep "," (
      lib.sort (a: b: a < b) (
        map (
          k:
          let
            v = ctx.${k};
          in
          "${k}=${
            if builtins.isAttrs v && v ? name then
              v.name
            else if builtins.isString v then
              v
            else if builtins.isInt v || builtins.isFloat v then
              toString v
            else
              "<${builtins.typeOf v}:${k}>"
          }"
        ) (builtins.attrNames ctx)
      )
    );

  defaultState = {
    # --- Flat state (global by design, not scoped) ---
    seen = _: { };
    pathSet = _: { };

    # --- Scope-partitioned output state (handlers write here) ---
    scopedClassImports = _: { };
    scopedAspectPolicies = _: { };
    scopedDeferredIncludes = _: { };
    scopedIncludesChain = _: { };
    scopedConstraintRegistry = _: { };
    scopedConstraintFilters = _: { };
    scopedRoutes = _: { };
    scopedInstantiates = _: { };
    scopedProvides = _: { };
    scopedForwardSpecs = _: { };
    scopedEmittedLocs = _: { };

    # --- Scope-prefixed bookkeeping (future: scope-prefixed keys) ---
    includeSeen = _: { };

    # --- Scope tree tracking ---
    # Sentinel scope for bare handler use (tests that bypass mkPipeline).
    # mkPipeline overrides this with the real rootScopeId.
    rootScopeId = "__unscoped";
    currentScope = "__unscoped";
    scopeContexts = _: { };
    scopeParent = _: { };
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
      rootScopeId = mkScopeId ctx;
    in
    fx.handle {
      handlers = composeHandlers rootHandlers extraHandlers;
      state =
        defaultState
        // extraState
        // {
          inherit rootScopeId;
          currentScope = rootScopeId;
          scopeContexts = _: { ${rootScopeId} = ctx; };
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
                ;
            };
            # Enrichment-only args must NOT be advertised to NixOS — they
            # don't exist in _module.args and would trigger infinite recursion
            # when NixOS tries to look them up. Standard den args (host, user)
            # DO exist in _module.args and are safe to advertise.
            enrichmentOnlyKeys = builtins.attrNames enrichmentKeys;
            # Strip args that NixOS can't resolve from the module's advertised
            # functionArgs. Without this, NixOS probes _module.args.${name}
            # for every advertised arg and crashes when the key doesn't exist.
            # Wrapped modules: strip enrichment-only keys (injected by den).
            # Unwrapped modules: strip args with defaults not in ctx.
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
    }:
    let
      result = mkPipeline { inherit class; } { inherit self ctx; };
    in
    let
      # Build per-scope wrapped class imports from scoped partitions.
      scopeContexts = result.state.scopeContexts null;
      scopedClassImportsRaw = result.state.scopedClassImports null;
      wrappedPerScope = lib.mapAttrs (
        scopeId: scopeClasses:
        let
          scopeCtx = scopeContexts.${scopeId} or ctx;
        in
        wrapCollectedClasses scopeCtx scopeClasses
      ) scopedClassImportsRaw;

      # Flatten per-scope wrapped imports into a single classImports map.
      # Scoped partitions are the sole source of truth — flat classImports
      # no longer needed (flake output forwards eliminated by policy.instantiate).
      wrappedClassImports = builtins.foldl' (
        acc: scopeData:
        lib.zipAttrsWith (_: builtins.concatLists) [
          acc
          scopeData
        ]
      ) { } (builtins.attrValues wrappedPerScope);

      # Apply Tier 1 routes (reads wrappedPerScope, produces new entries).
      scopedRoutes = result.state.scopedRoutes null;
      withRoutes = route.applyRoutes {
        inherit scopedRoutes wrappedPerScope;
        classImports = wrappedClassImports;
      };

      # Apply policy.provide — inject new modules directly into target classes.
      scopedProvides = result.state.scopedProvides null;
      allProvides = lib.concatLists (lib.attrValues scopedProvides);
      withProvides = builtins.foldl' (
        acc: spec:
        let
          targetClass = spec.class;
          path = spec.path or [ ];
          scopeCtx = scopeContexts.${spec.sourceScopeId} or ctx;
          wrapped = den.lib.aspects.fx.aspect.wrapClassModule {
            ctx = scopeCtx;
            module = spec.module;
            aspectPolicy = null;
            globalPolicy = null;
          };
          wrappedMod =
            if wrapped.unsatisfied or false then
              [ ]
            else
              let
                mod = wrapped.module;
                nested =
                  if path == [ ] then
                    mod
                  else
                    args:
                    let
                      fullArgs = args // (args.config._module.args or { });
                      resolved = if builtins.isFunction mod then mod fullArgs else mod;
                    in
                    {
                      config = lib.setAttrByPath path resolved;
                    };
                loc = "${targetClass}@<provide>/${lib.concatStringsSep "/" path}";
              in
              [ (lib.setDefaultModuleLocation loc nested) ];
        in
        acc
        // {
          ${targetClass} = (acc.${targetClass} or [ ]) ++ wrappedMod;
        }
      ) withRoutes.classImports allProvides;

      # Apply entity instantiation — evaluate entities and place in flake output.
      scopedInstantiates = result.state.scopedInstantiates null;
      allInstantiates = lib.concatLists (lib.attrValues scopedInstantiates);
      instantiateModules = lib.concatMap (
        spec:
        let
          entity = spec;
          hasOutput = (entity.intoAttr or [ ]) != [ ];
        in
        if !hasOutput then
          [ ]
        else
          let
            # Home entities provide pkgs; OS entities provide system for hostPlatform.
            instantiateArgs =
              if entity ? pkgs then
                {
                  inherit (entity) pkgs;
                  modules = [ entity.mainModule ];
                }
              else
                {
                  modules = [
                    entity.mainModule
                  ]
                  ++ lib.optional (entity ? system) {
                    nixpkgs.hostPlatform = lib.mkDefault entity.system;
                  };
                };
            evaluated = entity.instantiate instantiateArgs;
          in
          [ { config = lib.setAttrByPath ([ "flake" ] ++ entity.intoAttr) evaluated; } ]
      ) allInstantiates;
      withInstantiates = withProvides // {
        flake = (withProvides.flake or [ ]) ++ instantiateModules;
      };

      # Apply Tier 2 forwards with per-scope isolation.
      # installPolicies propagates root-scope forward specs to child scopes
      # during the pipeline walk. Child-scope copies read per-scope source
      # for user isolation. Root-scope-only forwards (no child copies) read
      # from merged classImports (unchanged behavior).
      rootScopeId = mkScopeId ctx;
      rawForwardSpecs = lib.concatLists (lib.attrValues (result.state.scopedForwardSpecs null));

      # Dedup by adapterKey@scope. Suppress root-scope specs when child
      # copies exist (child copies handle the forward with scope isolation).
      forwardSpecs =
        let
          # Collect adapterKeys that have child-scope specs.
          childScopeKeys = builtins.foldl' (
            acc: s:
            let
              ak = s.adapterKey or null;
            in
            if ak != null && s.sourceScopeId != rootScopeId then acc // { ${ak} = true; } else acc
          ) { } rawForwardSpecs;

          go =
            seen: specs:
            if specs == [ ] then
              [ ]
            else
              let
                s = builtins.head specs;
                rest = builtins.tail specs;
                ak = s.adapterKey or null;
                # Suppress root-scope spec when child copies handle the same forward.
                isRedundantRoot = ak != null && s.sourceScopeId == rootScopeId && childScopeKeys ? ${ak};
                # Scope-specific dedup: same forward at different scopes must NOT
                # be deduped — each scope needs its own isolated execution.
                key = if ak != null then "${ak}@${s.sourceScopeId}" else null;
              in
              if isRedundantRoot then
                go seen rest
              else if key != null && seen ? ${key} then
                go seen rest
              else
                [ s ] ++ go (if key != null then seen // { ${key} = true; } else seen) rest;
        in
        go { } rawForwardSpecs;

      # Collect class modules from a forward aspect (recursing into includes).
      collectClassMods =
        cls: aspect:
        let
          own = if aspect ? ${cls} then [ aspect.${cls} ] else [ ];
          nested = builtins.concatMap (collectClassMods cls) (aspect.includes or [ ]);
        in
        own ++ nested;

      applyForwardSpecs =
        specs: classImports:
        builtins.foldl'
          (
            acc: spec:
            let
              sid = spec.sourceScopeId;
              # Source modules: per-scope for child-scope forwards (scope isolation),
              # merged for root-scope forwards (aggregate/alias forwards unchanged).
              sourceModules =
                if sid != rootScopeId then
                  # Per-scope + filtered root fallback: only den.default's shared
                  # modules (identity = "default") from root scope. Host-specific
                  # aspect modules (identity = host name) are excluded to prevent
                  # leaking into user forwards.
                  let
                    ownModules = (acc.perScope.${sid} or { }).${spec.fromClass} or [ ];
                    rootModules = (acc.perScope.${rootScopeId} or { }).${spec.fromClass} or [ ];
                    isDenDefaultModule =
                      mod:
                      let
                        k = mod.key or mod._file or "";
                      in
                      lib.hasSuffix "@default" k;
                    sharedModules = builtins.filter isDenDefaultModule rootModules;
                  in
                  sharedModules ++ ownModules
                else
                  acc.classImports.${spec.fromClass} or [ ];
              # If no source modules in the pipeline, resolve the forward's
              # source aspect directly. This handles forwards whose fromAspect
              # produces a synthetic aspect not walked during the pipeline
              # (the old sub-pipeline was removed).
              resolvedSourceModules =
                if sourceModules != [ ] then
                  sourceModules
                else if spec ? sourceAspect then
                  let
                    normalized = den.lib.aspects.normalizeRoot spec.sourceAspect;
                    sourceCtx = scopeContexts.${sid} or ctx;
                    sourceResult = fxResolve {
                      class = spec.fromClass;
                      self = normalized;
                      ctx =
                        sourceCtx // den.lib.aspects.fx.aspect.ctxFromHandlers (spec.sourceAspect.__scopeHandlers or { });
                    };
                  in
                  sourceResult.imports
                else
                  [ ];
              rawSourceModule = {
                imports = resolvedSourceModules;
              };
              sourceModule = spec.mapModule rawSourceModule;
              forwardAspect = handlers.buildForwardAspect spec sourceModule;
              newMods = collectClassMods spec.intoClass forwardAspect;
            in
            {
              classImports = acc.classImports // {
                ${spec.intoClass} = (acc.classImports.${spec.intoClass} or [ ]) ++ newMods;
              };
              # Track forward outputs per-scope for chained forward support.
              perScope = acc.perScope // {
                ${sid} = (acc.perScope.${sid} or { }) // {
                  ${spec.intoClass} = ((acc.perScope.${sid} or { }).${spec.intoClass} or [ ]) ++ newMods;
                };
              };
            }
          )
          {
            inherit classImports;
            perScope = wrappedPerScope;
          }
          specs;

      forwarded =
        if forwardSpecs == [ ] then
          withInstantiates
        else
          (applyForwardSpecs forwardSpecs withInstantiates).classImports;

    in
    {
      imports = forwarded.${class} or [ ];
    };
in
{
  inherit
    composeHandlers
    defaultHandlers
    defaultState
    mkPipeline
    mkScopeId
    fxFullResolve
    fxResolve
    wrapCollectedClasses
    ;
}
