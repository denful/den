# Effect handler: compile-conditional
# Evaluates guard against path-set, emits includes or tombstones.
# Guards that fail are deferred for re-evaluation when the pathSet grows;
# drain-conditionals resolves them at entity boundary.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;
  inherit (den.lib.aspects.fx.aspect) emitIncludes;
  inherit (den.lib.schemaUtil) schemaEntityKindsSet;
  inherit (import ./state-util.nix) scopedAppend;

  tombstoneAll =
    aspects:
    builtins.foldl' (
      acc: aspect:
      fx.bind acc (
        results:
        let
          tombstone = identity.tombstone aspect { guardFailed = true; };
        in
        fx.bind (fx.send "resolve-complete" tombstone) (_: fx.pure (results ++ [ tombstone ]))
      )
    ) (fx.pure [ ]) aspects;

  # In-flight pathSet is not class-partitioned, so forClass approximates
  # as forAnyClass (may produce false positives across classes, never false
  # negatives). Accurate enough for guards — the pathSet reflects all
  # classes walked so far in the current resolution.
  mkPipelineHasAspect = pathSet: {
    __functor = _: ref: pathSet ? ${identity.key ref};
    forClass = _: ref: pathSet ? ${identity.key ref};
    forAnyClass = ref: pathSet ? ${identity.key ref};
  };

  # Build guard context with entity-shaped stubs so predicates written as
  # ({ host, ... }: host.hasAspect ref) work without touching config.resolved.
  # Uses scope handler keys to identify entity kinds without evaluating the
  # handlers (which would force entity config and cycle).
  mkGuardCtx =
    pathSet: scopeHandlers:
    let
      pipelineHasAspect = mkPipelineHasAspect pathSet;
      handlerKeys = builtins.attrNames scopeHandlers;
      entityKeys = builtins.filter (k: schemaEntityKindsSet ? ${k}) handlerKeys;
      entityStubs = lib.genAttrs entityKeys (_: {
        hasAspect = pipelineHasAspect;
      });
    in
    {
      hasAspect = ref: pathSet ? ${identity.key ref};
    }
    // entityStubs;

  # Defer a conditional for re-evaluation at entity boundary.
  deferConditional =
    condNode:
    let
      stub = {
        name = condNode.name or "<when>";
        meta =
          (builtins.removeAttrs (condNode.meta or { }) [
            "guard"
            "aspects"
          ])
          // {
            deferred = true;
            guardDeferred = true;
          };
        includes = [ ];
      };
    in
    fx.bind (fx.send "defer-conditional" condNode) (
      _: fx.bind (fx.send "resolve-complete" stub) (_: fx.pure [ ])
    );
in
{
  compileConditionalHandler = {
    "compile-conditional" =
      { param, state }:
      let
        condNode = param.aspect;
      in
      {
        resume = fx.bind (fx.send "get-path-set" null) (
          pathSet:
          let
            guardCtx = mkGuardCtx pathSet (condNode.__scopeHandlers or { });
            pass = condNode.meta.guard guardCtx;
          in
          if pass then
            emitIncludes {
              __parentScopeHandlers = condNode.__scopeHandlers or null;
              __parentCtxId = condNode.__ctxId or null;
            } condNode.meta.aspects
          else
            deferConditional condNode
        );
        inherit state;
      };
  };

  # Store a deferred conditional in scoped state.
  deferConditionalHandler = {
    "defer-conditional" =
      { param, state }:
      {
        resume = null;
        state = scopedAppend state "scopedDeferredConditionals" state.currentScope param;
      };
  };

  # Re-evaluate deferred conditionals against the final pathSet.
  # Called at entity boundary after the full tree walk completes.
  drainConditionalsHandler = {
    "drain-conditionals" =
      { param, state }:
      let
        scope = state.currentScope;
        allScoped = (state.scopedDeferredConditionals or (_: { })) null;
        scopeDeferred = allScoped.${scope} or [ ];
      in
      if scopeDeferred == [ ] then
        {
          resume = fx.pure [ ];
          inherit state;
        }
      else
        {
          resume = fx.bind (fx.send "get-path-set" null) (
            pathSet:
            let
              go =
                idx: acc:
                if idx >= builtins.length scopeDeferred then
                  acc
                else
                  let
                    condNode = builtins.elemAt scopeDeferred idx;
                    guardCtx = mkGuardCtx pathSet (condNode.__scopeHandlers or { });
                    pass = condNode.meta.guard guardCtx;
                  in
                  go (idx + 1) (
                    fx.bind acc (
                      prev:
                      if pass then
                        fx.bind (emitIncludes {
                          __parentScopeHandlers = condNode.__scopeHandlers or null;
                          __parentCtxId = condNode.__ctxId or null;
                        } condNode.meta.aspects) (results: fx.pure (prev ++ results))
                      else
                        fx.bind (tombstoneAll condNode.meta.aspects) (tombstones: fx.pure (prev ++ tombstones))
                    )
                  );
            in
            go 0 (fx.pure [ ])
          );
          # Clear deferred conditionals for this scope.
          state = state // {
            scopedDeferredConditionals = _: allScoped // { ${scope} = [ ]; };
          };
        };
  };
}
