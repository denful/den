# Effect handler: register-aspect-policy
# Registers policies declared on aspects into scope-partitioned state.
_:
let
  inherit (import ./state-util.nix) scopedMerge;

  registerAspectPolicyHandler = {
    "register-aspect-policy" =
      { param, state }:
      let
        entry = {
          inherit (param) fn ownerIdentity;
        };
        # The registry is the one scoped field that merges rather than appends,
        # so a repeated key is a silent drop. Derive it here from the owner's
        # identity instead of letting each caller name its own: a caller that
        # reaches for a local name registers `tools/to-users` for every aspect
        # owning a sub-aspect called `tools`, and all but the last vanish.
        # `label` separates several registrations by one owner (one per
        # `provides` key); an owner registering once needs none.
        label = param.label or null;
        registryKey = if label == null then param.ownerIdentity else "${param.ownerIdentity}/${label}";
      in
      {
        resume = null;
        state = scopedMerge state "scopedAspectPolicies" state.currentScope {
          ${registryKey} = entry;
        };
      };
  };
in
{
  inherit registerAspectPolicyHandler;
}
