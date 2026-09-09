# Effect handler: compile-conditional
# Evaluates guards with exclude-aware hasAspect. Guards that fail are
# deferred for re-evaluation when the pathSet grows (drain-conditionals).
# Constraint registry is read eagerly — emitPolicyEffectsThen registers
# excludes before processing includes, so guards see per-scope excludes.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;
  inherit (den.lib.aspects.fx.aspect) emitIncludes chainWrap;
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

  # Collect constraint registry entries from the current scope and all
  # ancestor scopes via scopeParent (the shared cycle-guarded walk from
  # constraint.nix), then NORMALIZES ownerChain to [] so isExcludedInScope treats
  # all collected entries as in-scope (scope ancestry already establishes
  # relevance — the guard view does not need the within-scope includesChain filter
  # that check-constraint keeps).
  collectScopeConstraints =
    scopedRegistry: scopeParentMap: scope:
    lib.mapAttrs (_: entries: map (e: e // { ownerChain = [ ]; }) entries) (
      collectScopedConstraints scopedRegistry scopeParentMap scope
    );

  # Reuse the shared scope+ancestor walk + the constraint lookup from
  # constraint.nix (avoids duplicating the cycle-guarded walk and the prefix-
  # matching identity logic).
  inherit (import ./constraint.nix { inherit lib den; })
    lookupEntries
    isAncestorChain
    collectScopedConstraints
    foldScopeAncestors
    ;

  # Union the per-scope path sets over `scope` + its ancestors — an entity's
  # own + inherited membership, EXCLUDING sibling / other-entity subtrees (the
  # same cycle-guarded walk as collectScopedConstraints, merging with `//` since
  # the pathSet is membership booleans). Guards consult THIS instead of the
  # fleet-wide flat pathSet, which accumulated every walked scope's aspects and
  # leaked sibling membership in an eval-order-dependent way (#613: a host's
  # `hasAspect` guard saw an aspect another host included). pathSetByScope mirrors
  # the flat set's key space (identity.nix), so the guard's `pathSet ? identity.key
  # ref` check works unchanged against this union.
  scopedPathSet =
    pathSetByScope: scopeParentMap: scope:
    foldScopeAncestors (a: b: a // b) scopeParentMap (s: pathSetByScope.${s} or { }) scope;

  # Check if an aspect identity is excluded in a constraint registry.
  isExcludedInScope =
    { constraintRegistry, includesChain }:
    nodeIdentity:
    let
      allEntries = lookupEntries constraintRegistry nodeIdentity;
      inScope =
        entry:
        entry.type == "exclude"
        && (
          (entry.scope or "global") == "global" || isAncestorChain includesChain (entry.ownerChain or [ ])
        );
    in
    builtins.any inScope allEntries;

  # The pathSet handed in is the scope-restricted union (scopedPathSet over
  # currentScope + ancestors, #613) — an entity's own + inherited membership.
  # It is not class-partitioned, so forClass approximates as forAnyClass (may
  # produce false positives across classes within that scope, never false
  # negatives).
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

  # Chain-push the conditional around payload emission so sibling guards'
  # anonymous payloads get distinct names instead of dedup-colliding.
  emitGuardedAspects =
    condNode:
    chainWrap (identity.aspectPath condNode) true (
      emitIncludes {
        __parentScopeHandlers = condNode.__scopeHandlers or null;
        __parentCtxId = condNode.__ctxId or null;
      } condNode.meta.aspects
    );

  # Defer a conditional for re-evaluation at entity boundary.
  deferConditional =
    condNode:
    let
      # Bookkeeping only — deliberately NOT a rebuild of condNode. The node is
      # queued intact by the defer-conditional effect below and re-evaluated at
      # the entity boundary; this record exists so the deferred conditional
      # still registers an identity, and every resolve-complete consumer
      # (identity.collectPathsHandler, trace.nix) reads name/meta and nothing
      # else. guard/aspects are stripped because the payload has not fired, and
      # `includes = [ ]` states that this marker carries no children of its own
      # — a reset, not a dropped carry-forward.
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
        # Evaluate guard with exclude awareness. The constraint registry
        # has already been populated by emitPolicyEffectsThen (which
        # registers excludes before processing includes).
        # Scope the guard's membership view to this entity's own subtree
        # (currentScope + ancestors), NOT the fleet-wide flat pathSet — the
        # same scope+ancestor restriction already applied to the constraint
        # registry below. Otherwise a sibling host that included the aspect
        # earlier in the walk leaks into this guard (#613).
        resume = fx.bind fx.effects.state.get (
          currentState:
          let
            scope = currentState.currentScope;
            pathSetByScope = (currentState.pathSetByScope or (_: { })) null;
            scopeParentMap = (currentState.scopeParent or (_: { })) null;
            scopedRegistry = (currentState.scopedConstraintRegistry or (_: { })) null;
            constraintRegistry = collectScopeConstraints scopedRegistry scopeParentMap scope;
            guardCtx = mkGuardCtx {
              pathSet = scopedPathSet pathSetByScope scopeParentMap scope;
              inherit constraintRegistry;
              scopeHandlers = condNode.__scopeHandlers or { };
            };
            pass = condNode.meta.guard guardCtx;
          in
          if pass then emitGuardedAspects condNode else deferConditional condNode
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

  # Re-evaluate deferred conditionals with exclude-aware hasAspect.
  # Uses scope-specific constraint registry (not flat) so per-scope
  # excludes only affect their own scope.
  # Fixed-point iteration: each pass re-reads state. Convergence
  # guaranteed — each progressing pass resolves ≥1 guard.
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
              drainPass =
                pending: prevResults:
                fx.bind fx.effects.state.get (
                  currentState:
                  let
                    # Build scope-specific constraint registry AND membership
                    # set from this deferred conditional's scope + ancestors —
                    # tux's excludes don't leak to pingu, and a sibling host's
                    # aspects don't leak into this guard's hasAspect (#613).
                    scopedRegistry = (currentState.scopedConstraintRegistry or (_: { })) null;
                    scopeParentMap = (currentState.scopeParent or (_: { })) null;
                    pathSetByScope = (currentState.pathSetByScope or (_: { })) null;
                    constraintRegistry = collectScopeConstraints scopedRegistry scopeParentMap scope;
                    guardPathSet = scopedPathSet pathSetByScope scopeParentMap scope;
                    len = builtins.length pending;
                    go =
                      idx: acc:
                      if idx >= len then
                        acc
                      else
                        let
                          condNode = builtins.elemAt pending idx;
                          guardCtx = mkGuardCtx {
                            pathSet = guardPathSet;
                            inherit constraintRegistry;
                            scopeHandlers = condNode.__scopeHandlers or { };
                          };
                          pass = condNode.meta.guard guardCtx;
                        in
                        go (idx + 1) (
                          fx.bind acc (
                            prev:
                            if pass then
                              fx.bind (emitGuardedAspects condNode) (
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
                );

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
          state = state // {
            scopedDeferredConditionals = _: allScoped // { ${scope} = [ ]; };
          };
        };
  };
}
