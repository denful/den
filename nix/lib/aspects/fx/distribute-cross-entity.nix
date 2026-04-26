# Cross-entity trait distribution.
#
# After phase 1 pipeline completes, distribute collected provide-to
# emissions to target entity configs. Groups by target entity identity,
# then merges trait data per-target using collection strategy from schemas.
#
# Input: list of { targetEntity, traits } from sibling routing
#   where traits = { traitName = data; } (list or attrset per strategy)
# Output: { "<target-name>" = { "<traitName>" = merged-data; }; }
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx.handlers) constantHandler;

  collectTrait = den.lib.aspects.fx.handlers.collectTrait;

  # Group emissions by target entity name.
  # Returns: { "<target-name>" = [ { targetEntity, traits }... ]; }
  groupByTarget =
    emissions:
    builtins.foldl' (
      acc: emission:
      let
        targetId =
          if
            emission.targetEntity != null
            && builtins.isAttrs emission.targetEntity
            && emission.targetEntity ? name
          then
            emission.targetEntity.name
          else
            builtins.throw "den: cross-entity distribution: emission missing targetEntity.name";
      in
      acc
      // {
        ${targetId} = (acc.${targetId} or [ ]) ++ [ emission ];
      }
    ) { } emissions;

  # Merge trait data from multiple emissions for a single target.
  # Uses collection strategy from traitSchemas.
  mergeTraits =
    traitSchemas: emissions:
    builtins.foldl' (
      acc: emission:
      let
        traits = emission.traits or { };
      in
      builtins.foldl' (
        inner: traitName:
        let
          schema = traitSchemas.${traitName} or { };
          strategy = if builtins.isAttrs schema then schema.collection or "list" else "list";
          existing = inner.${traitName} or (if strategy == "map" then { } else [ ]);
          newValue = traits.${traitName};
          merged = collectTrait {
            inherit
              strategy
              traitName
              existing
              newValue
              ;
          };
        in
        inner // { ${traitName} = merged; }
      ) acc (builtins.attrNames traits)
    ) { } emissions;

  # Distribute cross-entity trait emissions.
  # Returns: { "<target-name>" = { "<traitName>" = merged-data; }; }
  distributeCrossEntityTraits =
    {
      traitSchemas ? { },
    }:
    emissions:
    if emissions == [ ] then
      { }
    else
      let
        grouped = groupByTarget emissions;
      in
      lib.mapAttrs (_targetId: targetEmissions: mergeTraits traitSchemas targetEmissions) grouped;

  # Build constantHandler bindings from distributed trait data (backward compat).
  # Each trait becomes a constantHandler binding so parametric aspects
  # can consume it via bind.fn.
  distribute =
    {
      traitSchemas ? { },
    }:
    emissions:
    let
      distributed = distributeCrossEntityTraits { inherit traitSchemas; } emissions;
    in
    lib.mapAttrs (_targetId: traitData: constantHandler traitData) distributed;

in
{
  inherit
    groupByTarget
    mergeTraits
    distributeCrossEntityTraits
    distribute
    ;
}
