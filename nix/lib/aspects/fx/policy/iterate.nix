# Fixed-point enrichment loop — dispatch, enrich, re-dispatch until stable.
{
  lib,
  fx,
  constantHandler,
  aspectToEffect,
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
    fx.bind (fx.send "drain-deferred" enrichedCtx) (
      satisfiable:
      builtins.foldl' (
        acc: deferred:
        fx.bind acc (
          _:
          aspectToEffect (deferred.child // { __scopeHandlers = scopeHandlers; })
        )
      ) (fx.pure null) satisfiable
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
          newEnrichKeys = builtins.filter (k: !accEnrichment ? ${k}) (
            builtins.attrNames dispatched.enrichment
          );
          combinedEffects = mergeEffects accEffects dispatched;
        in
        if newEnrichKeys == [ ] then
          fx.bind (fx.effects.state.modify (
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
          )) (_: emitFinalEffects entityKind currentCtx accEnrichment dispatched combinedEffects)
        else if iteration >= maxPolicyIterations then
          throw "den: installPolicies enrichment iteration exceeded ${toString maxPolicyIterations} — likely a cycle (${entityKind})"
        else
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
              st:
              st
              // {
                scopeContexts = _: (st.scopeContexts null) // { ${st.currentScope} = enrichedCtx; };
              }
            ))
            (
              _:
              fx.bind (fx.effects.scope.provide enrichHandlers (drainEnrichmentDeferred enrichedCtx)) (
                _: go (iteration + 1) combinedEnrichment combinedEffects updatedFired nextResolveCtx
              )
            );
    in
    go;
in
{
  inherit emptyAcc iterate;
}
