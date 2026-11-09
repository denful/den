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
  inherit (import ./constraint.nix { inherit lib den; })
    scopedConstraintsFor
    isPolicyInstanceExcluded
    isOriginExcluded
    ;
in
{
  mkDispatchPoliciesHandler = mkDispatch: {
    "dispatch-policies" =
      { param, state }:
      let
        # Entity-scoped (scope + ancestors, NOT fleet-wide) — a sibling entity's
        # policy-exclude must not filter this scope's policies (#613 analog).
        registry = scopedConstraintsFor state;
        # Applied once, outside the lambda — see isPolicyExcluded's currying note.
        excluded = isPolicyInstanceExcluded state state.currentScope registry;
        originExcluded = isOriginExcluded state registry;
        filteredPolicies = lib.filterAttrs (
          name: p: !(excluded name p) && !(originExcluded name p)
        ) param.aspectPolicies;
      in
      {
        resume = mkDispatch filteredPolicies param.firedPolicies param.resolveCtx;
        inherit state;
      };
  };
}
