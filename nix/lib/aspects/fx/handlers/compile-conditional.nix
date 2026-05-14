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

  # Collect constraint registry entries from the current scope and all
  # ancestor scopes via scopeParent. Normalizes ownerChain to [] so
  # isExcludedInScope treats all collected entries as in-scope.
  collectScopeConstraints =
    scopedRegistry: scopeParentMap:
    let
      go =
        scope: acc:
        let
          scopeEntries = scopedRegistry.${scope} or { };
          # Normalize entries: clear ownerChain since scope ancestry
          # already establishes relevance.
          normalized = lib.mapAttrs (_: entries: map (e: e // { ownerChain = [ ]; }) entries) scopeEntries;
          merged = lib.zipAttrsWith (_: builtins.concatLists) [
            acc
            normalized
          ];
          parent = scopeParentMap.${scope} or null;
        in
        if parent == null then merged else go parent merged;
    in
    go;

  # Reuse constraint lookup from constraint.nix to avoid duplicating
  # the prefix-matching logic (identity path splitting + prefix search).
  inherit (import ./constraint.nix { inherit lib den; }) lookupEntries;

  # Check if an aspect identity is excluded in a constraint registry.
  isExcludedInScope =
    { constraintRegistry, includesChain }:
    nodeIdentity:
    let
      allEntries = lookupEntries constraintRegistry nodeIdentity;
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
        # Evaluate guard with exclude awareness. The constraint registry
        # has already been populated by emitPolicyEffectsThen (which
        # registers excludes before processing includes).
        resume = fx.bind (fx.send "get-path-set" null) (
          pathSet:
          fx.bind fx.effects.state.get (
            currentState:
            let
              scopedRegistry = (currentState.scopedConstraintRegistry or (_: { })) null;
              scopeParentMap = (currentState.scopeParent or (_: { })) null;
              constraintRegistry =
                collectScopeConstraints scopedRegistry scopeParentMap currentState.currentScope
                  { };
              guardCtx = mkGuardCtx {
                inherit pathSet constraintRegistry;
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
          )
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
                fx.bind (fx.send "get-path-set" null) (
                  pathSet:
                  fx.bind fx.effects.state.get (
                    currentState:
                    let
                      # Build scope-specific constraint registry from current
                      # scope and ancestors — tux's excludes don't leak to pingu.
                      scopedRegistry = (currentState.scopedConstraintRegistry or (_: { })) null;
                      scopeParentMap = (currentState.scopeParent or (_: { })) null;
                      constraintRegistry = collectScopeConstraints scopedRegistry scopeParentMap scope { };
                      len = builtins.length pending;
                      go =
                        idx: acc:
                        if idx >= len then
                          acc
                        else
                          let
                            condNode = builtins.elemAt pending idx;
                            guardCtx = mkGuardCtx {
                              inherit pathSet constraintRegistry;
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
