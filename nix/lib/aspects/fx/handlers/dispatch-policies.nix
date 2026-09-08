# Effect handler constructor: dispatch-policies
# Wraps mkDispatch to make policy dispatch observable.
# Exported as a constructor (mkDispatchPoliciesHandler) because mkDispatch
# lives in policy/dispatch.nix and cannot be imported directly here.
# resolve-children.nix constructs this via policy/default.nix.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (import ./constraint.nix { inherit lib den; }) scopedConstraintsFor isPolicyExcluded;
in
{
  mkDispatchPoliciesHandler = mkDispatch: {
    "dispatch-policies" =
      { param, state }:
      let
        # Entity-scoped (scope + ancestors, NOT fleet-wide) — a sibling entity's
        # policy-exclude must not filter this scope's policies (#613 analog).
        registry = scopedConstraintsFor state;
        filteredPolicies = lib.filterAttrs (
          name: _: !isPolicyExcluded state state.currentScope registry name
        ) param.aspectPolicies;
      in
      {
        resume = mkDispatch filteredPolicies param.firedPolicies param.resolveCtx;
        inherit state;
      };
  };
}
