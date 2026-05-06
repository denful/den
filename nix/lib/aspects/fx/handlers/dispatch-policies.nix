# Effect handler constructor: dispatch-policies
# Wraps mkDispatch to make policy dispatch observable.
# Exported as a constructor (mkDispatchPoliciesHandler) because mkDispatch
# lives in policy/dispatch.nix and cannot be imported directly here.
# resolve-children.nix constructs this via policy/default.nix.
_: {
  mkDispatchPoliciesHandler = mkDispatch: {
    "dispatch-policies" =
      { param, state }:
      {
        resume = mkDispatch param.aspectPolicies param.firedPolicies param.resolveCtx;
        inherit state;
      };
  };
}
