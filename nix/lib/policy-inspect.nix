# Lightweight policy inspection utility.
# Calls resolve functions directly — no full pipeline run.
# Essential for debugging "why did host X get this module?"
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.synthesizePolicies) ctxSatisfies resolveArgsSatisfied activePoliciesFor;

  # Inspect all applicable policies for a given entity kind and context.
  # Returns: { policyName = { targetKey, targets, from, to, as, routing }; }
  #
  # Cheap: only calls resolve functions, no pipeline execution.
  inspect =
    { kind, context }:
    let
      active = activePoliciesFor kind context;
      matching = lib.filterAttrs (
        _: policy:
        policy.from == kind && ctxSatisfies policy.from context && resolveArgsSatisfied policy context
      ) active;
    in
    lib.mapAttrs (
      _name: policy:
      let
        targetKey = if policy.as != "" then policy.as else policy.to;
        rawResult = policy.resolve context;
        targets = if builtins.isList rawResult then rawResult else [ rawResult ];
      in
      {
        inherit targetKey targets;
        inherit (policy) from to;
        as = policy.as;
        routing = if policy.from == policy.to then "sibling" else "child";
      }
    ) matching;
in
{
  inherit inspect;
}
