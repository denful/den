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
  #
  # An entity's `name` is NOT always injective across entities of one kind: a
  # home's `name` is force-set to the bare user name
  # (nix/lib/entities/home.nix), so two standalone homes `user@hostA` /
  # `user@hostB` both rendered `home=user` and collapsed onto ONE scope — their
  # collected class content merged and each flake output yielded the other's
  # configuration. Entities therefore expose `__scopeName`, their registry key
  # (see nix/lib/entities/_types.nix), which is unique per kind per system.
  # It defaults to `name`, so only kinds that rewrite `name` differ here.
  # Synthetic context values (e.g. a bare `{ name = ...; }` host) carry no
  # `__scopeName` and fall back to `name`.
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
            if builtins.isAttrs v && v ? __scopeName then
              v.__scopeName
            else if builtins.isAttrs v && v ? name then
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
    # Per-scope path set: scopeId → { pathKey → true } (both the ctx-qualified
    # nodeKey and the base key). Byproduct of the structural walk, bucketed by
    # the scope that owns each node — the SINGLE membership record. Powers the
    # projected (in-context) hasAspect and the scope-restricted guard membership
    # check (#613); the flat scope-agnostic view is its union
    # (identity.flattenPathSetByScope). Thunked to survive per-step deepSeq.
    pathSetByScope = _: { };
    # Full resolved nodes keyed by unique identity, for entity.aspects.
    resolvedNodes = _: { };

    # --- Scope-partitioned output state (handlers write here) ---
    scopedClassImports = _: { };
    scopedAspectPolicies = _: { };
    scopedDeferredIncludes = _: { };
    scopedDeferredConditionals = _: { };
    scopedIncludesChain = _: { };
    scopedConstraintRegistry = _: { };
    # Flat filter list only (excludes/substitutes are entity-scoped via
    # scopedConstraintRegistry; filters have no scoped registry).
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
    # Spec→scope link (the entity scope is recorded, never name-infix matched):
    # when resolve.to creates an entity scope (push-scope with entityKind set), record
    # the scope it created keyed by (parentScope, entity id_hash). An instantiate
    # spec — registered at the SAME parent scope, carrying the same entity record
    # (hence id_hash) — looks its entity scope up directly. Key combines parent +
    # id_hash because id_hash is context-free (kind+name, NOT ancestry), so two
    # same-name entities on different systems share an id_hash but have distinct
    # parent (system=…) scopes. See resolve.nix entityScopeFor.
    scopeByEntity = _: { };

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
