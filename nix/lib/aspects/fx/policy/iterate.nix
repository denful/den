# Fixed-point enrichment loop — dispatch, enrich, re-dispatch until stable.
{
  lib,
  fx,
  identity,
  constantHandler,
  mkDispatch,
  emitPolicyEffectsThen,
  policyEmitIncludes,
  processSchemaResolves,
}:
let
  maxPolicyIterations = 10;

  # Empty accumulator for iteration.
  emptyAcc = {
    schemaEffects = [ ];
    includeEffects = [ ];
    excludeEffects = [ ];
    routeEffects = [ ];
    instantiateEffects = [ ];
    provideEffects = [ ];
  };

  # Merge new dispatch results into the accumulator.
  mergeEffects = accEffects: dispatched: {
    schemaEffects = accEffects.schemaEffects ++ dispatched.schemaEffects;
    includeEffects = accEffects.includeEffects ++ dispatched.includeEffects;
    excludeEffects = accEffects.excludeEffects ++ dispatched.excludeEffects;
    routeEffects = accEffects.routeEffects ++ dispatched.routeEffects;
    instantiateEffects = accEffects.instantiateEffects ++ dispatched.instantiateEffects;
    provideEffects = accEffects.provideEffects ++ dispatched.provideEffects;
  };

  # Emit final effects when enrichment has stabilized.
  emitFinalEffects =
    entityKind: currentCtx: accEnrichment: dispatched: combinedEffects:
    let
      enrichedCtx = currentCtx // accEnrichment // dispatched.enrichment;
      includeAspects = map (e: e.value) combinedEffects.includeEffects;
      hasSchemaResolves = combinedEffects.schemaEffects != [ ];
    in
    emitPolicyEffectsThen combinedEffects (
      if hasSchemaResolves then
        processSchemaResolves entityKind includeAspects combinedEffects.schemaEffects enrichedCtx
      else
        policyEmitIncludes combinedEffects.includeEffects
    );

  # Drain deferred aspects after enrichment context widen (results discarded).
  drainEnrichmentDeferred =
    enrichedCtx:
    let
      scopeHandlers = constantHandler enrichedCtx;
    in
    fx.bind (fx.send "drain" enrichedCtx) (
      satisfiable:
      builtins.foldl' (
        acc: deferred:
        fx.bind acc (
          _:
          let
            child = deferred.child // {
              __scopeHandlers = scopeHandlers;
            };
          in
          fx.send "resolve" {
            aspect = child;
            identity = identity.key child;
            ctx = enrichedCtx;
            gated = true;
          }
        )
      ) (fx.pure null) satisfiable
    );

  # Record which policies fired at this scope (for late-dispatch cross-sibling visibility).
  recordFired =
    entityKind: updatedFired:
    fx.effects.state.modify (
      st:
      let
        dispatchKey = "${entityKind}@${st.currentScope}";
      in
      st
      // {
        firedPolicyNames =
          _:
          let
            all = (st.firedPolicyNames or (_: { })) null;
          in
          all // { ${dispatchKey} = updatedFired; };
      }
    );

  # Widen enrichment: update scope context, drain deferred, continue iteration.
  widenAndContinue =
    go: iteration: entityKind: currentCtx: accEnrichment: dispatched: combinedEffects: updatedFired:
    let
      combinedEnrichment = accEnrichment // dispatched.enrichment;
      enrichedCtx = currentCtx // combinedEnrichment;
      enrichHandlers = constantHandler combinedEnrichment;
      nextResolveCtx = enrichedCtx // {
        __entityKind = entityKind;
      };
    in
    fx.bind
      (fx.effects.state.modify (
        st: st // { scopeContexts = _: (st.scopeContexts null) // { ${st.currentScope} = enrichedCtx; }; }
      ))
      (
        _:
        fx.bind (fx.effects.scope.provide enrichHandlers (drainEnrichmentDeferred enrichedCtx)) (
          _: go (iteration + 1) combinedEnrichment combinedEffects updatedFired nextResolveCtx
        )
      );

  # Fixed-point iteration.
  iterate =
    allDirectPolicies: aspectPolicies: entityKind: currentCtx:
    let
      go =
        iteration: accEnrichment: accEffects: firedPolicies: currentResolveCtx:
        let
          dispatched = mkDispatch allDirectPolicies aspectPolicies firedPolicies currentResolveCtx;
          newFiredNames = builtins.filter (n: !(firedPolicies ? ${n})) dispatched.firedNames;
          updatedFired = firedPolicies // lib.genAttrs newFiredNames (_: true);
          # Invariant: enrichment is key-monotonic — keys are only added, never
          # changed.  Convergence checks new keys only; value changes don't
          # trigger re-dispatch.
          newEnrichKeys = builtins.filter (k: !accEnrichment ? ${k}) (
            builtins.attrNames dispatched.enrichment
          );
          combinedEffects = mergeEffects accEffects dispatched;
        in
        if newEnrichKeys == [ ] then
          fx.bind (recordFired entityKind updatedFired) (
            _: emitFinalEffects entityKind currentCtx accEnrichment dispatched combinedEffects
          )
        else if iteration >= maxPolicyIterations then
          throw "den: installPolicies enrichment iteration exceeded ${toString maxPolicyIterations} — likely a cycle (${entityKind})"
        else
          widenAndContinue go iteration entityKind currentCtx accEnrichment dispatched combinedEffects
            updatedFired;
    in
    go;
in
{
  inherit emptyAcc iterate;
}
