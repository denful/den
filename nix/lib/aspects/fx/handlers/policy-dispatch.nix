# Compile active policies into per-policy named effect handlers.
#
# Each policy becomes a handler for "policy:<name>". The transition
# handler sends these effects to dispatch policies individually,
# enabling granular tracing, per-policy override via scope.provide,
# and routing metadata for provide-to.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.synthesizePolicies)
    ctxSatisfies
    resolveArgsSatisfied
    activePoliciesFor
    ;

  # Compile all active policies into named effect handlers.
  # Returns: { "policy:<name>" = handler; ... }
  #
  # Each handler receives pipeline context as param and returns
  # { targets, routing } where routing carries policy metadata
  # for the transition handler's routing decision.
  compilePolicyHandlers =
    let
      policies = den.policies or { };
    in
    lib.mapAttrs' (name: policy: {
      name = "policy:${name}";
      value =
        { param, state }:
        let
          ctx = param.ctx;
          stageName = param.stageName;
          active = activePoliciesFor stageName ctx;
          isActive = active ? ${name};
          scopeOk = isActive && ctxSatisfies policy.from ctx;
          argsOk = scopeOk && resolveArgsSatisfied policy ctx;
          rawResult = if argsOk then policy.resolve ctx else [ ];
          targets =
            if builtins.isList rawResult then
              rawResult
            else
              builtins.trace "den: policy ${name}: resolve returned non-list, coercing" [ rawResult ];
          targetKey = if policy.as != "" then policy.as else policy.to;
        in
        {
          resume =
            if targets == [ ] then
              null
            else
              {
                inherit targets;
                routing = {
                  inherit (policy) from to;
                  inherit targetKey;
                  policyName = name;
                };
              };
          inherit state;
        };
    }) policies;

  # Return list of "policy:<name>" effect names for policies matching a stage.
  # Returns ALL matching policies, not just active ones — activation is
  # context-dependent (entity.policies varies per entity), so it's checked
  # at dispatch time inside each handler, not at compile time.
  policyEffectNamesFor =
    stageName:
    let
      policies = den.policies or { };
    in
    lib.concatLists (
      lib.mapAttrsToList (name: policy: lib.optional (policy.from == stageName) "policy:${name}") policies
    );
in
{
  inherit compilePolicyHandlers policyEffectNamesFor;
}
