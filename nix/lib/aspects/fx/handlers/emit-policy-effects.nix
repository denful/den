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
        includeAspects = map (e: e.value) effects.includeEffects;
        hasSchemaResolves = effects.schemaEffects != [ ];
      in
      {
        resume = emitPolicyEffectsThen effects (
          if hasSchemaResolves then
            processSchemaResolves entityKind includeAspects effects.schemaEffects enrichedCtx
          else
            policyEmitIncludes effects.includeEffects
        );
        inherit state;
      };
  };
}
