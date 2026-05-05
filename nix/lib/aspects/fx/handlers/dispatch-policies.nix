# Effect handler constructor: dispatch-policies
# Wraps mkDispatch to make policy dispatch observable.
# Exported as a constructor (mkDispatchPoliciesHandler) because mkDispatch
# lives in policy/dispatch.nix and cannot be imported directly here.
# pipeline.nix calls the constructor with mkDispatch bound.
_: {
  mkDispatchPoliciesHandler = mkDispatch: {
    "dispatch-policies" =
      { param, state }:
      {
        resume = mkDispatch param.directPolicies param.aspectPolicies param.firedPolicies param.resolveCtx;
        inherit state;
      };
  };
}
