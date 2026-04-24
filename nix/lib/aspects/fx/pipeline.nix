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
  defaultHandlers =
    { class, ctx }:
    handlers.constantHandler (
      {
        inherit class;
        "aspect-chain" = [ ];
      }
      // ctx
    )
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
    // resolvePolicyHandler
    // resolveTargetHandler
    // handlers.forwardHandler
    // handlers.provideToHandler
    // fx.effects.state.handler;

  resolvePolicyHandler = {
    "resolve-policy" =
      { param, state }:
      {
        resume = den.lib.synthesizePolicies.mergePolicyInto param.stageName param.existingInto;
        inherit state;
      };
  };

  resolveTargetHandler = {
    "resolve-target" =
      { param, state }:
      let
        stageAspect = lib.attrByPath param.path null (den.stages or { });
        targetName = if stageAspect != null then stageAspect.name or "" else "";
        stageName = lib.concatStringsSep "." param.path;
        existingInto = if stageAspect != null then stageAspect.meta.into or null else null;
        mergedInto = den.lib.synthesizePolicies.mergePolicyInto targetName existingInto;
        # Tag with __ctxStage so the chainHandler tracks stage transitions.
        withStage = a: a // { __ctxStage = stageName; };
      in
      {
        resume =
          if stageAspect != null && mergedInto != null then
            withStage (
              stageAspect
              // {
                meta = (stageAspect.meta or { }) // {
                  into = mergedInto;
                };
              }
            )
          else if stageAspect != null then
            withStage stageAspect
          else
            null;
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
      existingInto = self.meta.into or self.into or null;

      bootstrapAndResolve =
        fx.bind
          (fx.send "resolve-policy" {
            stageName = self.name or "";
            inherit existingInto;
          })
          (
            mergedInto:
            let
              effectiveSelf =
                if mergedInto != null && mergedInto != existingInto then
                  self
                  // {
                    meta = (self.meta or { }) // {
                      into = mergedInto;
                    };
                  }
                else
                  self;
            in
            aspectToEffect effectiveSelf
          );

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
