{
  lib,
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) handlers identity;
  # Compose two handler sets: b's resume wins, a's state wins.
  # Used for tracing: tracingHandler (b) controls resume,
  # defaultHandlers (a) accumulates paths/imports.
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
            inherit (rb) state;
          };
        in
        {
          inherit (rb) resume;
          inherit (ra) state;
        }
      ) shared;
    in
    a // b // sharedComposed;

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
    // handlers.ctxSeenHandler
    // identity.pathSetHandler
    // identity.collectPathsHandler
    // handlers.registerAspectPolicyHandler
    // handlers.registerRouteHandler
    // handlers.registerInstantiateHandler
    // handlers.provideHandler
    // handlers.registerPipeEffectHandler
    // handlers.registerSpawnHandler
    // resolveEntityHandler
    // handlers.pushScopeHandler
    // handlers.restoreScopeHandler
    // handlers.propagateRoutesHandler
    // handlers.recordFiredHandler
    // handlers.widenContextHandler
    // handlers.resolveSchemaEntityHandler
    // handlers.gateHandler
    // handlers.resolveHandler
    // handlers.compileHandler
    // handlers.compileForwardHandler
    // handlers.compileConditionalHandler
    // handlers.deferConditionalHandler
    // handlers.drainConditionalsHandler
    // handlers.compileParametricHandler
    // handlers.compileStaticHandler
    // handlers.bindHandler
    // handlers.deferHandler
    // handlers.drainHandler
    // handlers.scopeWidenHandler
    // handlers.classifyHandler
    // handlers.emitClassesHandler
    // handlers.resolveChildrenHandler
    // handlers.dispatchPoliciesHandler
    // handlers.emitPolicyEffectsHandler
    // fx.effects.state.handler;

  # resolve-entity resolves an entity by kind using resolveEntity.
  resolveEntityHandler = {
    "resolve-entity" =
      { param, state }:
      let
        inherit (param) kind;
        scope = state.currentScope;
        currentCtx = if scope == null then { } else (state.scopeContexts null).${scope} or { };
        entity = den.lib.resolveEntity kind currentCtx;
      in
      {
        resume = entity;
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
    # Per-scope path set: scopeId → { basePathKey → true }. Byproduct of the
    # structural walk, bucketed by the scope that owns each node. Powers the
    # projected (in-context) hasAspect. Thunked to survive per-step deepSeq.
    pathSetByScope = _: { };

    # --- Scope-partitioned output state (handlers write here) ---
    scopedClassImports = _: { };
    scopedAspectPolicies = _: { };
    # Pre-merged flat view (avoid O(S) rebuild per installPolicies call).
    flatAspectPolicies = { };
    scopedDeferredIncludes = _: { };
    scopedDeferredConditionals = _: { };
    scopedIncludesChain = _: { };
    scopedConstraintRegistry = _: { };
    scopedConstraintFilters = _: { };
    # Pre-merged flat views (avoid O(S) rebuild per check-constraint call).
    flatConstraintRegistry = { };
    flatConstraintFilters = [ ];
    scopedRoutes = _: { };
    scopedInstantiates = _: { };
    scopedProvides = _: { };
    scopedPipeEffects = _: { };
    scopedSpawns = _: { };
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
    firedPolicyNames = _: { };
    dispatchedPolicies = _: { };
    registeredRouteKeys = _: { };
    inLateDispatch = false;
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
      bootstrapAndResolve = fx.send "resolve" {
        aspect = self;
        identity = identity.key self;
        ctx = ctx;
        gated = true;
      };

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

  resolveModule = import ./resolve.nix { inherit lib den; };
  inherit (resolveModule) wrapCollectedClasses;
  fxResolve = resolveModule.fxResolve mkPipeline;
  fxResolveWithPaths = resolveModule.fxResolveWithPaths mkPipeline;
  fxResolveImports = resolveModule.fxResolveImports mkPipeline;
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
    fxResolveWithPaths
    fxResolveImports
    wrapCollectedClasses
    ;
}
