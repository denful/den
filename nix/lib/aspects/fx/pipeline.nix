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
  inherit (den.lib.aspects.fx.traceUtil) traceSummary traceDetail;
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
    // handlers.checkDedupHandler
    // handlers.resolveConditionalHandler
    // handlers.resolveParametricHandler
    // handlers.resolveAspectHandler
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
    // handlers.resolveSchemaEntityHandler
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
        kind = traceDetail "resolve-entity kind=${param.kind} scope=${state.currentScope or "?"}" param.kind;
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

    # --- Policy dispatch tracking ---
    # Maps "entityKind@scopeId" → list of policy names fired in that scope.
    # Used by lateDispatchPass to identify policies registered after a scope resolved.
    firedPolicyNames = _: { };
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

  inherit (import ./wrap-classes.nix { inherit lib den; }) wrapCollectedClasses;

  # Drop-in resolve shape: returns { imports = [...] }.
  fxResolve =
    {
      class,
      self,
      ctx,
    }:
    let
      _traceEntry = traceSummary "fxResolve called — class=${class} ctx={${lib.concatStringsSep "," (builtins.attrNames ctx)}}";
      result = _traceEntry (mkPipeline { inherit class; } { inherit self ctx; });
    in
    let
      # Build per-scope wrapped class imports from scoped partitions.
      scopeContexts = result.state.scopeContexts null;
      scopedClassImportsRaw = result.state.scopedClassImports null;

      # === TRACING: scope inventory ===
      _traceScopes = traceSummary "scopes = [${lib.concatStringsSep ", " (builtins.attrNames scopedClassImportsRaw)}]";
      # === TRACING: per-scope raw module counts ===
      _traceRawCounts = lib.mapAttrs (
        scopeId: scopeClasses:
        lib.mapAttrs (
          cls: entries:
          traceSummary "raw[${scopeId}][${cls}] = ${toString (builtins.length entries)} modules" entries
        ) scopeClasses
      ) scopedClassImportsRaw;

      wrappedPerScope = lib.mapAttrs (
        scopeId: scopeClasses:
        let
          scopeCtx = scopeContexts.${scopeId} or ctx;
        in
        wrapCollectedClasses scopeCtx scopeClasses
      ) (_traceScopes _traceRawCounts);

      # === TRACING: per-scope wrapped module counts + identities ===
      _traceWrapped = lib.mapAttrs (
        scopeId: scopeClasses:
        lib.mapAttrs (
          cls: entries:
          let
            keys = map (e: e.key or e._file or "<no-key>") entries;
            count = builtins.length entries;
          in
          traceSummary "wrapped[${scopeId}][${cls}] = ${toString count} modules: [${lib.concatStringsSep ", " keys}]" entries
        ) scopeClasses
      ) wrappedPerScope;

      # Flatten per-scope wrapped imports into a single classImports map.
      # Scoped partitions are the sole source of truth — flat classImports
      # no longer needed (flake output forwards eliminated by policy.instantiate).
      wrappedClassImports =
        let
          raw = builtins.foldl' (
            acc: scopeData:
            lib.zipAttrsWith (_: builtins.concatLists) [
              acc
              scopeData
            ]
          ) { } (builtins.attrValues _traceWrapped);
        in
        # === TRACING: post-flatten totals ===
        lib.mapAttrs (
          cls: entries: traceSummary "flat[${cls}] = ${toString (builtins.length entries)} modules" entries
        ) raw;

      # Apply policy.provide — inject new modules directly into target classes.
      # Provides run BEFORE routes so that complex forward-derived routes
      # (which read from classImports/perScope) can see provide-injected modules.
      # This preserves the old ordering: provides → forwards.
      # Dedup: same policy firing at multiple scopes produces identical provides.
      # Keyed by policyName + class + path to preserve legitimate multi-policy provides.
      scopedProvides = result.state.scopedProvides null;
      allProvides =
        let
          raw = lib.concatLists (lib.attrValues scopedProvides);
          go =
            seen: specs:
            if specs == [ ] then
              [ ]
            else
              let
                s = builtins.head specs;
                rest = builtins.tail specs;
                pn = s.__providePolicyName or null;
                key = if pn != null then "${pn}/${s.class}/${lib.concatStringsSep "/" (s.path or [ ])}" else null;
              in
              if key != null && seen ? ${key} then
                go seen rest
              else
                [ s ] ++ go (if key != null then seen // { ${key} = true; } else seen) rest;
        in
        go { } raw;
      providesResult =
        builtins.foldl'
          (
            acc: spec:
            let
              targetClass = spec.class;
              path = spec.path or [ ];
              sid = spec.sourceScopeId;
              scopeCtx = scopeContexts.${sid} or ctx;
              rawModule = if path == [ ] then spec.module else lib.setAttrByPath path spec.module;
              wrapped = den.lib.aspects.fx.aspect.wrapClassModule {
                ctx = scopeCtx;
                module = rawModule;
                aspectPolicy = null;
                globalPolicy = null;
              };
              wrappedMod =
                if wrapped.unsatisfied or false then
                  [ ]
                else
                  let
                    loc = "${targetClass}@<provide>/${lib.concatStringsSep "/" path}";
                  in
                  [ (lib.setDefaultModuleLocation loc wrapped.module) ];
            in
            {
              classImports = acc.classImports // {
                ${targetClass} = (acc.classImports.${targetClass} or [ ]) ++ wrappedMod;
              };
              perScope = acc.perScope // {
                ${sid} = (acc.perScope.${sid} or { }) // {
                  ${targetClass} = ((acc.perScope.${sid} or { }).${targetClass} or [ ]) ++ wrappedMod;
                };
              };
            }
          )
          {
            classImports = wrappedClassImports;
            perScope = wrappedPerScope;
          }
          allProvides;

      withProvides = providesResult.classImports;
      wrappedPerScopeWithProvides = providesResult.perScope;

      # === TRACING: post-provides counts ===
      _traceProvides = lib.mapAttrs (
        cls: entries:
        let
          prevCount = builtins.length (wrappedClassImports.${cls} or [ ]);
          newCount = builtins.length entries;
          delta = newCount - prevCount;
        in
        if delta > 0 then
          traceSummary "provides[${cls}] added ${toString delta} modules (${toString prevCount} → ${toString newCount})" entries
        else
          entries
      ) withProvides;

      # Apply all routes — both simple (path nesting) and complex (forward-derived).
      # Runs after provides so complex routes can see provide-injected modules.
      scopedRoutes = result.state.scopedRoutes null;
      # === TRACING: route specs ===
      _traceScopedRoutes =
        let
          allRoutes = lib.concatLists (lib.attrValues scopedRoutes);
          routeDescs = map (
            r:
            let
              isComplex = r.__complexForward or false;
              from = r.fromClass or "?";
              into = r.intoClass or "?";
              path = lib.concatStringsSep "/" (r.path or [ ]);
              scope = r.sourceScopeId or "?";
              kind = if isComplex then "complex" else "simple";
              adapter = if r.adapterKey or null != null then " adapter=${r.adapterKey}" else "";
            in
            "${kind}: ${from}→${into} path=[${path}] scope=${scope}${adapter}"
          ) allRoutes;
        in
        traceSummary "${toString (builtins.length allRoutes)} routes: ${lib.concatStringsSep "; " routeDescs}" null;

      rootScopeId = builtins.seq _traceScopedRoutes (mkScopeId ctx);
      withRoutes = route.applyRoutes {
        inherit
          scopedRoutes
          scopeContexts
          ctx
          rootScopeId
          ;
        wrappedPerScope = wrappedPerScopeWithProvides;
        classImports = withProvides;
        inherit fxResolve;
        inherit (handlers) buildForwardAspect;
      };

      # === TRACING: post-routes counts ===
      _traceRoutes = lib.mapAttrs (
        cls: entries:
        let
          prevCount = builtins.length (_traceProvides.${cls} or [ ]);
          newCount = builtins.length entries;
          delta = newCount - prevCount;
        in
        if delta > 0 then
          traceSummary "routes[${cls}] added ${toString delta} modules (${toString prevCount} → ${toString newCount})" entries
        else
          entries
      ) withRoutes.classImports;

      # Apply entity instantiation — evaluate entities and place in flake output.
      scopedInstantiates = result.state.scopedInstantiates null;
      allInstantiates = lib.concatLists (lib.attrValues scopedInstantiates);
      # === TRACING: instantiate specs ===
      _traceInstantiates =
        let
          descs = map (
            spec:
            let
              attr = lib.concatStringsSep "." (spec.intoAttr or [ ]);
              scope = spec.sourceScopeId or "?";
            in
            "${attr} (scope=${scope})"
          ) allInstantiates;
        in
        traceSummary "${toString (builtins.length allInstantiates)} instantiates: [${lib.concatStringsSep ", " descs}]" null;
      instantiateModules = builtins.seq _traceInstantiates (
        lib.concatMap (
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
              evaluated = traceSummary "INSTANTIATE materializing ${lib.concatStringsSep "." (entity.intoAttr or [ "?" ])}" (
                entity.instantiate instantiateArgs
              );
            in
            [ { config = lib.setAttrByPath ([ "flake" ] ++ entity.intoAttr) evaluated; } ]
        ) allInstantiates
      );
      withInstantiates = _traceRoutes // {
        flake = (_traceRoutes.flake or [ ]) ++ instantiateModules;
      };

      # === TRACING: per-module import tracing with key info ===
      finalModules = withInstantiates.${class} or [ ];

      # Dump key vs _file for each module to verify dedup capability
      _traceKeyInfo =
        let
          info = lib.imap0 (
            i: mod:
            let
              hasKey = builtins.isAttrs mod && mod ? key;
              hasFile = builtins.isAttrs mod && mod ? _file;
              isFn = builtins.isFunction mod;
              label =
                if hasKey then
                  "KEY=${mod.key}"
                else if hasFile then
                  "_file=${mod._file}"
                else if isFn then
                  "fn#${toString i}"
                else
                  "bare#${toString i}";
            in
            "[${toString i}] ${label}"
          ) finalModules;
        in
        traceSummary "${toString (builtins.length finalModules)} modules for class=${class}: ${lib.concatStringsSep "; " info}" null;

    in
    {
      imports = builtins.seq _traceKeyInfo finalModules;
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
