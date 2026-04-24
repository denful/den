# Phase 2 provide-to distribution.
#
# After phase 1 pipeline completes, distribute collected provide-to
# emissions to target entity configs. Groups by target entity identity,
# then by label. Labeled data is installed as constantHandler bindings
# on the target's resolution.
#
# For configs without cross-entity contributions, distribution is a no-op.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx.handlers) constantHandler;

  # Group provide-to emissions by target entity name, then by label.
  # Returns: { "<target-name>" = { "<label>" = [ data... ]; }; }
  groupByTarget =
    emissions:
    builtins.foldl' (
      acc: emission:
      let
        content = emission.content;
        targetId =
          if
            emission.targetEntity != null
            && builtins.isAttrs emission.targetEntity
            && emission.targetEntity ? name
          then
            emission.targetEntity.name
          else
            emission.label;
      in
      acc
      // {
        ${targetId} = (acc.${targetId} or { }) // {
          ${emission.label} =
            (acc.${targetId}.${emission.label} or [ ])
            ++ (if content != null then if builtins.isList content then content else [ content ] else [ ]);
        };
      }
    ) { } emissions;

  # Build extra handlers from grouped provide-to data.
  # Each label becomes a constantHandler binding so parametric aspects
  # can consume it via bind.fn ({ http-backends, ... }: ...).
  mkProvideToHandlers =
    labeledData:
    constantHandler (
      lib.mapAttrs (
        _label: dataList: lib.concatLists (map (d: if builtins.isList d then d else [ d ]) dataList)
      ) labeledData
    );

  # Distribute collected provide-to emissions.
  # Returns: { "<target-name>" = <handler-set>; } or { } if no emissions.
  distribute =
    emissions:
    if emissions == [ ] then
      { }
    else
      let
        grouped = groupByTarget emissions;
      in
      lib.mapAttrs (_targetId: labeledData: mkProvideToHandlers labeledData) grouped;
in
{
  inherit groupByTarget mkProvideToHandlers distribute;
}
