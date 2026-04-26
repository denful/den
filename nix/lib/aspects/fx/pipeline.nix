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
      # Use _traitNames (attrsOf bool) for cycle-free pipeline lookup.
      # den.schema.traits depends on den.aspects which triggers pipeline
      # resolution → cycle. _traitNames is populated independently.
      traitNames = den._traitNames or { };
      # For collection strategy, we need the schema. This is safe to access
      # in the handler itself (lazy), not during handler construction.
      traitSchemas = den.schema.traits or { };
    in
    handlers.traitArgHandler traitNames
    // handlers.constantHandler (
      {
        inherit class;
        "aspect-chain" = [ ];
      }
      // ctx
    )
    // handlers.traitCollectorHandler { inherit ctx traitSchemas; }
    // handlers.classCollectorHandler { targetClass = class; }
    // handlers.constraintRegistryHandler
    // handlers.chainHandler
    // handlers.includeHandler
    // handlers.transitionHandler
    // handlers.ctxSeenHandler
    // identity.pathSetHandler
    // identity.collectPathsHandler
    // handlers.deferredIncludeHandler
    // handlers.drainDeferredHandler
    // resolveTargetHandler
    // handlers.forwardHandler
    // handlers.provideToHandler
    // handlers.compilePolicyHandlers
    // fx.effects.state.handler;

  # resolve-target resolves a stage aspect by path using resolveStage.
  # Policies dispatch via per-policy named effects in the transition handler.
  resolveTargetHandler = {
    "resolve-target" =
      { param, state }:
      let
        stageExists = lib.attrByPath param.path null (den.stages or { }) != null;
        stageName = lib.concatStringsSep "." param.path;
        currentCtx = (state.currentCtx or (_: { })) null;
      in
      {
        resume = if stageExists then den.lib.resolveStage stageName currentCtx else null;
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
    imports = _: [ ];
    constraintRegistry = _: { };
    constraintFilters = _: [ ];
    pathSet = _: { };
    includesChain = _: [ ];
    deferredIncludes = _: [ ];
    provideTo = _: [ ];
    traits = _: { };
    deferredTraits = _: { };
    consumedTraits = _: { };
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
    }:
    mkPipeline { inherit class; } { inherit self ctx; };

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
    {
      imports = result.state.imports null;
    };
in
{
  inherit
    composeHandlers
    defaultHandlers
    defaultState
    mkPipeline
    fxFullResolve
    fxResolve
    ;
}
