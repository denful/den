# Fixed-point enrichment loop — dispatch, enrich, re-dispatch until stable.
{
  lib,
  fx,
  constantHandler,
  enterScope,
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
  mergeEffects =
    accEffects: dispatched:
    lib.zipAttrsWith (_: builtins.concatLists) [
      accEffects
      dispatched
    ];

  # Fixed-point iteration.
  iterate =
    aspectPolicies: entityKind: currentCtx:
    let
      go =
        iteration: accEnrichment: accEffects: firedPolicies: currentResolveCtx:
        fx.bind
          (fx.send "dispatch-policies" {
            inherit aspectPolicies firedPolicies;
            resolveCtx = currentResolveCtx;
          })
          (
            dispatched:
            let
              newFiredNames = builtins.filter (n: !(firedPolicies ? ${n})) dispatched.firedNames;
              updatedFired = firedPolicies // lib.genAttrs newFiredNames (_: true);
              # Invariant: enrichment is key-monotonic — keys are only added, never
              # changed.  Convergence checks new keys only; value changes don't
              # trigger re-dispatch.
              newEnrichKeys = builtins.filter (k: !(accEnrichment ? ${k})) (
                builtins.attrNames dispatched.enrichment
              );
              combinedEffects = mergeEffects accEffects dispatched;
            in
            if newEnrichKeys == [ ] then
              let
                combinedEnrichment = accEnrichment // dispatched.enrichment;
                enrichedCtx = currentCtx // combinedEnrichment;
              in
              fx.bind
                (fx.send "record-fired" {
                  inherit entityKind;
                  firedPolicies = updatedFired;
                })
                (
                  _:
                  fx.bind
                    # Persist enrichment into scopeContexts so child scopes
                    # and the post-walk drain can see it.
                    (
                      if combinedEnrichment != { } then
                        fx.send "widen-context" {
                          enrichment = combinedEnrichment;
                          inherit currentCtx;
                        }
                      else
                        fx.pure null
                    )
                    (
                      _:
                      fx.send "emit-policy-effects" {
                        effects = combinedEffects;
                        inherit entityKind enrichedCtx;
                      }
                    )
                )
            else if iteration >= maxPolicyIterations then
              throw "den: enrichment cycle at ${entityKind} — fired: ${lib.concatStringsSep ", " (builtins.attrNames updatedFired)}, enrichment keys: ${
                lib.concatStringsSep ", " (builtins.attrNames (accEnrichment // dispatched.enrichment))
              }"
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
                (fx.send "widen-context" {
                  enrichment = combinedEnrichment;
                  currentCtx = currentCtx;
                })
                (
                  _:
                  fx.bind (enterScope enrichHandlers (fx.pure null)) (
                    _: go (iteration + 1) combinedEnrichment combinedEffects updatedFired nextResolveCtx
                  )
                )
          );
    in
    go;
in
{
  inherit emptyAcc iterate;
}
