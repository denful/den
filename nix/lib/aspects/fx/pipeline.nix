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
    // handlers.ctxSeenHandler
    // identity.pathSetHandler
    // identity.collectPathsHandler
    // handlers.registerAspectPolicyHandler
    // handlers.registerTraitSchemaHandler
    // handlers.getTraitSchemasHandler
    // handlers.deferredIncludeHandler
    // handlers.drainDeferredHandler
    // handlers.registerRouteHandler
    // handlers.registerInstantiateHandler
    // resolveEntityHandler
    // handlers.forwardHandler
    // handlers.dispatchPoliciesHandler
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
            else
              "<${builtins.typeOf v}:${k}>"
          }"
        ) (builtins.attrNames ctx)
      )
    );

  # Walk scope tree for trait inheritance.
  # "list": parent data ++ own data (accumulate up tree)
  # "map": parent data // own data (child overrides parent keys)
  # "single": own data only (no inheritance)
  inheritTraits =
    { scopedTraits, scopeParent }:
    scopeId: traitName: strategy:
    let
      emptyDefault = if strategy == "map" then { } else [ ];
      own = (scopedTraits.${scopeId} or { }).${traitName} or emptyDefault;
      parentId = scopeParent.${scopeId} or null;
      parentData =
        if parentId == null then
          emptyDefault
        else
          inheritTraits { inherit scopedTraits scopeParent; } parentId traitName strategy;
    in
    if strategy == "single" then
      own
    else if strategy == "map" then
      parentData // own
    else
      parentData ++ own;

  # Synthesize a traitModule for a specific scope with inheritance.
  traitModuleForScope =
    {
      scopedTraits,
      scopedDeferredTraits,
      scopeParent,
      traitSchemas,
    }:
    scopeId:
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
          inherited = inheritTraits { inherit scopedTraits scopeParent; } scopeId traitName strategy;
          deferred = (scopedDeferredTraits.${scopeId} or { }).${traitName} or [ ];
          deferredData = map (e: e.value moduleArgs) deferred;
        in
        if strategy == "single" then
          if deferredData != [ ] then builtins.head deferredData else inherited
        else if strategy == "map" then
          builtins.foldl' (acc: d: acc // d) inherited deferredData
        else
          inherited ++ deferredData
      ) traitSchemas;
    };

  defaultState = {
    # --- Flat state (global by design, not scoped) ---
    seen = _: { };
    pathSet = _: { };

    # --- Scope-partitioned output state (handlers write here) ---
    scopedClassImports = _: { };
    scopedTraits = _: { };
    scopedDeferredTraits = _: { };
    scopedConsumedTraits = _: { };
    scopedAspectPolicies = _: { };
    scopedDeferredIncludes = _: { };
    scopedIncludesChain = _: { };
    scopedConstraintRegistry = _: { };
    scopedConstraintFilters = _: { };
    scopedRoutes = _: { };
    scopedInstantiates = _: { };
    scopedForwardSpecs = _: { };
    scopedEmittedLocs = _: { };

    # --- Scope-prefixed bookkeeping (future: scope-prefixed keys) ---
    includeSeen = _: { };

    # --- Scope tree tracking ---
    # Sentinel scope for bare handler use (tests that bypass mkPipeline).
    # mkPipeline overrides this with the real rootScopeId.
    currentScope = "__unscoped";
    scopeContexts = _: { };
    scopeParent = _: { };

    # --- Global state ---
    traitSchemas = _: den.traits or { };
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
      traitSchemasVal = den.traits or { };
    in
    fx.handle {
      handlers = composeHandlers rootHandlers extraHandlers;
      state =
        defaultState
        // extraState
        // {
          inherit class;
          currentScope = rootScopeId;
          scopeContexts = _: { ${rootScopeId} = ctx; };
          traitSchemas = _: traitSchemasVal;
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
    }:
    let
      result = mkPipeline { inherit class; } { inherit self ctx; };
      traitSchemas = result.state.traitSchemas null;
      hasTraitSchemas = traitSchemas != { };

      # partialOk validation
      consumedTraits = builtins.foldl' (acc: v: acc // v) { } (
        builtins.attrValues ((result.state.scopedConsumedTraits or (_: { })) null)
      );
      deferredTraits = builtins.foldl' (acc: v: acc // v) { } (
        builtins.attrValues (result.state.scopedDeferredTraits null)
      );
      partialOkViolations = builtins.filter (
        traitName:
        consumedTraits ? ${traitName}
        && (deferredTraits.${traitName} or [ ]) != [ ]
        && !(traitSchemas.${traitName}.partialOk or false)
      ) (builtins.attrNames consumedTraits);

      # Trait module via scoped reads with inheritance.
      rootScopeId = mkScopeId ctx;
      scopeParent = result.state.scopeParent null;
      traitModule =
        if hasTraitSchemas then
          traitModuleForScope {
            scopedTraits = result.state.scopedTraits null;
            scopedDeferredTraits = result.state.scopedDeferredTraits null;
            inherit scopeParent traitSchemas;
          } rootScopeId
        else
          null;
    in
    if partialOkViolations != [ ] then
      throw "den: traits consumed at pipeline time have deferred (Tier 3) emissions without partialOk: ${builtins.concatStringsSep ", " partialOkViolations}. Set partialOk = true in the trait schema to allow partial pipeline-time data."
    else
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
          scopedTraits = result.state.scopedTraits null;
          inherit scopeParent traitSchemas;
          classImports = wrappedClassImports;
        };

        # Apply entity instantiation — evaluate entities and place in flake output.
        scopedInstantiates = result.state.scopedInstantiates null;
        allInstantiates = lib.concatLists (lib.attrValues scopedInstantiates);
        instantiateModules = lib.concatMap (
          spec:
          let
            # spec IS the entity — value unwrapping happens at emission
            # (transition.nix sends ie.value, not ie).
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
        withInstantiates = withRoutes.classImports // {
          flake = (withRoutes.classImports.flake or [ ]) ++ instantiateModules;
        };

        # Apply Tier 2 forwards — read source modules from wrappedPerScope
        # instead of running sub-pipelines.
        rawForwardSpecs = lib.concatLists (lib.attrValues (result.state.scopedForwardSpecs null));
        # Dedup by adapterKey — same forward can fire from multiple scopes
        # when dispatch-policies walks the same entity multiple times.
        forwardSpecs =
          let
            go =
              seen: specs:
              if specs == [ ] then
                [ ]
              else
                let
                  s = builtins.head specs;
                  rest = builtins.tail specs;
                  key = s.adapterKey or null;
                in
                if key != null && seen ? ${key} then
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
          builtins.foldl' (
            acc: spec:
            let
              sid = spec.sourceScopeId;
              # Source modules from acc.classImports — this includes:
              # 1. wrappedClassImports (all scopes flattened — has parent scope modules)
              # 2. Route-produced modules
              # 3. Modules from earlier forwards in this pass (chained forward support)
              # No separate scope chain walk needed — wrappedClassImports already merges
              # all scopes, and acc accumulates forward outputs.
              sourceModules = acc.classImports.${spec.fromClass} or [ ];
              rawSourceModule = {
                imports = sourceModules;
              };
              sourceModule = spec.mapModule rawSourceModule;
              forwardAspect = handlers.buildForwardAspect spec sourceModule;
              newMods = collectClassMods spec.intoClass forwardAspect;
            in
            {
              classImports = acc.classImports // {
                ${spec.intoClass} = (acc.classImports.${spec.intoClass} or [ ]) ++ newMods;
              };
            }
          ) { inherit classImports; } specs;

        forwarded =
          if forwardSpecs == [ ] then
            withInstantiates
          else
            (applyForwardSpecs forwardSpecs withInstantiates).classImports;

      in
      {
        imports = (forwarded.${class} or [ ]) ++ lib.optional hasTraitSchemas traitModule;
      };
in
{
  inherit
    composeHandlers
    defaultHandlers
    defaultState
    inheritTraits
    traitModuleForScope
    mkPipeline
    mkScopeId
    fxFullResolve
    fxResolve
    wrapCollectedClasses
    ;
}
