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

  # Check if an aspect identity is excluded in the current scope.
  # Mirrors the constraint lookup in check-constraint (constraint.nix)
  # but only checks for excludes, not substitutes or filters.
  isExcludedInScope =
    { constraintRegistry, includesChain }:
    nodeIdentity:
    let
      parts = lib.splitString "/" nodeIdentity;
      prefixes = lib.genList (i: lib.concatStringsSep "/" (lib.take (i + 1) parts)) (
        builtins.length parts - 1
      );
      exact = constraintRegistry.${nodeIdentity} or [ ];
      allEntries =
        if constraintRegistry == { } then
          exact
        else if builtins.length parts > 1 then
          exact ++ builtins.concatMap (p: constraintRegistry.${p} or [ ]) prefixes
        else
          exact;
      isAncestor = ownerChain: lib.take (builtins.length ownerChain) includesChain == ownerChain;
      inScope =
        entry:
        entry.type == "exclude"
        && ((entry.scope or "global") == "global" || isAncestor (entry.ownerChain or [ ]));
    in
    builtins.any inScope allEntries;

  # In-flight pathSet is not class-partitioned, so forClass approximates
  # as forAnyClass (may produce false positives across classes, never false
  # negatives). Accurate enough for guards — the pathSet reflects all
  # classes walked so far in the current resolution.
  mkPipelineHasAspect = pathSet: excludeCheck: {
    __functor =
      _: ref:
      let
        k = identity.key ref;
      in
      pathSet ? ${k} && !excludeCheck k;
    forClass =
      _: ref:
      let
        k = identity.key ref;
      in
      pathSet ? ${k} && !excludeCheck k;
    forAnyClass =
      ref:
      let
        k = identity.key ref;
      in
      pathSet ? ${k} && !excludeCheck k;
  };

  # Build guard context with entity-shaped stubs so predicates written as
  # ({ host, ... }: host.hasAspect ref) work without touching config.resolved.
  # Uses scope handler keys to identify entity kinds without evaluating the
  # handlers (which would force entity config and cycle).
  # Exclude-aware: consults the constraint registry to respect per-scope
  # policy excludes, so hasAspect returns false for excluded aspects.
  mkGuardCtx =
    {
      pathSet,
      scopeHandlers,
      constraintRegistry ? { },
      includesChain ? [ ],
    }:
    let
      excludeCheck = isExcludedInScope { inherit constraintRegistry includesChain; };
      pipelineHasAspect = mkPipelineHasAspect pathSet excludeCheck;
      handlerKeys = builtins.attrNames scopeHandlers;
      entityKeys = builtins.filter (k: schemaEntityKindsSet ? ${k}) handlerKeys;
      entityStubs = lib.genAttrs entityKeys (_: {
        hasAspect = pipelineHasAspect;
      });
    in
    {
      hasAspect =
        ref:
        let
          k = identity.key ref;
        in
        pathSet ? ${k} && !excludeCheck k;
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
            guardCtx = mkGuardCtx {
              inherit pathSet;
              scopeHandlers = condNode.__scopeHandlers or { };
            };
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

  # Re-evaluate deferred conditionals against the final pathSet and
  # constraint registry. Iterates to fixed point: each pass re-reads
  # state, evaluates remaining guards, and re-enqueues failures.
  # Convergence: each pass that makes progress resolves ≥1 guard,
  # strictly shrinking pending. No progress → cross-dependent → tombstone.
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
          resume =
            let
              # Single pass: read pathSet + constraints, partition guards.
              drainPass =
                pending: prevResults:
                fx.bind (fx.send "get-path-set" null) (
                  pathSet:
                  fx.bind fx.effects.state.get (
                    currentState:
                    let
                      constraintRegistry = currentState.flatConstraintRegistry or { };
                      includesChain = ((currentState.scopedIncludesChain or (_: { })) null).${scope} or [ ];
                      len = builtins.length pending;
                      go =
                        idx: acc:
                        if idx >= len then
                          acc
                        else
                          let
                            condNode = builtins.elemAt pending idx;
                            guardCtx = mkGuardCtx {
                              inherit pathSet constraintRegistry includesChain;
                              scopeHandlers = condNode.__scopeHandlers or { };
                            };
                            pass = condNode.meta.guard guardCtx;
                          in
                          go (idx + 1) (
                            fx.bind acc (
                              prev:
                              if pass then
                                fx.bind
                                  (emitIncludes {
                                    __parentScopeHandlers = condNode.__scopeHandlers or null;
                                    __parentCtxId = condNode.__ctxId or null;
                                  } condNode.meta.aspects)
                                  (
                                    results:
                                    fx.pure {
                                      emitted = prev.emitted ++ results;
                                      failed = prev.failed;
                                      progressed = true;
                                    }
                                  )
                              else
                                fx.pure {
                                  inherit (prev) emitted progressed;
                                  failed = prev.failed ++ [ condNode ];
                                }
                            )
                          );
                    in
                    go 0 (
                      fx.pure {
                        emitted = prevResults;
                        failed = [ ];
                        progressed = false;
                      }
                    )
                  )
                );

              # Fixed-point loop: iterate until no progress.
              # Convergence guaranteed: each pass that makes progress resolves
              # ≥1 guard, strictly shrinking pending. When no progress is made
              # the remaining guards are cross-dependent — tombstone them.
              iterate =
                pending: prevResults:
                fx.bind (drainPass pending prevResults) (
                  result:
                  if result.failed == [ ] then
                    fx.pure result.emitted
                  else if !result.progressed then
                    fx.bind (tombstoneAll (builtins.concatMap (n: n.meta.aspects) result.failed)) (
                      tombstones: fx.pure (result.emitted ++ tombstones)
                    )
                  else
                    iterate result.failed result.emitted
                );
            in
            iterate scopeDeferred [ ];
          # Clear deferred conditionals for this scope.
          state = state // {
            scopedDeferredConditionals = _: allScoped // { ${scope} = [ ]; };
          };
        };
  };
}
