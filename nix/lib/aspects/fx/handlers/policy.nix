# Effect handler: register-aspect-policy
# Registers policies declared on aspects into scope-partitioned state.
{ lib, ... }:
let
  inherit (import ./state-util.nix) scopedMerge;
  inherit (import ../policy/registrant.nix { inherit lib; }) registrantOnRegister;
  inherit (import ./provenance.nix { inherit lib; }) stackTokenOf;

  registerAspectPolicyHandler = {
    "register-aspect-policy" =
      { param, state }:
      let
        # The registrant is fixed where the policy registers: dispatched later at
        # a descendant, it still applies to this entity (#694 §11a R1).
        entry = {
          inherit (param) fn;
          registrant = registrantOnRegister state state.currentScope;
          # Registered inside a cross-provider include (`provides.to-hosts`,
          # `provides.<host>`): the policy is part of what that provider
          # delivers, so its includes are emitted under the provider's token
          # wherever it fires. Read from den's provenance stack.
          provenance = stackTokenOf state state.currentScope;
          # Where it registered: a repeat of an aspect on it deduplicated under
          # a provider tags what this policy emits, as it tags the aspect's
          # static content (handlers/provenance.nix locsOf).
          chain = ((state.scopedIncludesChain or (_: { })) null).${state.currentScope} or [ ];
          # Den's provides policies set their includes' provenance themselves.
          setsProvenance = param.setsProvenance or false;
        }
        // (if param ? fnSlot then { inherit (param) fnSlot; } else { });
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
