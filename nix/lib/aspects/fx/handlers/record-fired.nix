# Effect handler: record-fired
# Records which policies fired at a scope for late-dispatch cross-sibling visibility.
# Extracted from policy/iterate.nix recordFired.
_: {
  recordFiredHandler = {
    "record-fired" =
      { param, state }:
      let
        dispatchKey = "${param.entityKind}@${state.currentScope}";
        all = (state.firedPolicyNames or (_: { })) null;
      in
      {
        resume = null;
        state = state // {
          firedPolicyNames = _: all // { ${dispatchKey} = param.firedPolicies; };
        };
      };
  };
}
