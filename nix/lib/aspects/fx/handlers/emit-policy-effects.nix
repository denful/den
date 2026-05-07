# Effect handler constructor: emit-policy-effects
# Emits classified policy effects (excludes, routes, provides, instantiates, includes).
# Exported as a constructor (mkEmitPolicyEffectsHandler) because processSchemaResolves
# is built from policy/schema.nix and cannot be imported directly here.
{ den, ... }:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;
  apply = import ../policy/apply.nix { inherit fx identity; };
  inherit (apply) emitPolicyEffectsThen policyEmitIncludes;
in
{
  mkEmitPolicyEffectsHandler = processSchemaResolves: {
    "emit-policy-effects" =
      { param, state }:
      let
        inherit (param) effects entityKind enrichedCtx;
        hasSchemaResolves = effects.schemaEffects != [ ];
        # Separate include effects: cross-provider includes (from policies that
        # also produced schema resolves) go with processSchemaResolves.
        # Independent includes (from policies that only produced includes) get
        # emitted directly via policyEmitIncludes.  Without this separation,
        # unrelated policies' includes would be incorrectly bundled into schema
        # entity resolution when multiple policies fire at the same scope.
        crossProviderIncludes = builtins.filter (
          e:
          builtins.any (
            se: (se.__sourcePolicyName or "") == (e.__sourcePolicyName or "")
          ) effects.schemaEffects
        ) effects.includeEffects;
        independentIncludes = builtins.filter (
          e:
          !builtins.any (
            se: (se.__sourcePolicyName or "") == (e.__sourcePolicyName or "")
          ) effects.schemaEffects
        ) effects.includeEffects;
        includeAspects = map (e: e.value) crossProviderIncludes;
      in
      {
        resume = emitPolicyEffectsThen effects (
          if hasSchemaResolves then
            fx.bind (processSchemaResolves entityKind includeAspects effects.schemaEffects enrichedCtx) (
              schemaResults:
              fx.bind (policyEmitIncludes independentIncludes { }) (
                includeResults: fx.pure (schemaResults ++ includeResults)
              )
            )
          else
            policyEmitIncludes effects.includeEffects { }
        );
        inherit state;
      };
  };
}
