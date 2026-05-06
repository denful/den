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

  # Check if a policy name is excluded by any constraint in the registry.
  isExcluded =
    registry: name:
    let
      entries = registry.${name} or [ ];
    in
    builtins.any (e: e.type == "exclude") entries;
in
{
  mkDispatchPoliciesHandler = mkDispatch: {
    "dispatch-policies" =
      { param, state }:
      let
        registry = state.flatConstraintRegistry or { };
        filteredPolicies = lib.filterAttrs (name: _: !isExcluded registry name) param.aspectPolicies;
      in
      {
        resume = mkDispatch filteredPolicies param.firedPolicies param.resolveCtx;
        inherit state;
      };
  };
}
