# The policy name claim, shared by registerPolicy (children.nix) and den's
# provides policies (provide.nix): every registration into the per-scope
# policy registry claims its name here first, so a second, different
# registration under a taken name is displaced to a chain-qualified identity
# instead of silently overwriting the first (O4), and the same registration
# seen again keeps its identity (O5). `value` is what tells them apart, by
# whole-value `==`.
{ lib, den }:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;
  inherit (import ../handlers/constraint.nix { inherit lib den; }) resolveClaim;
in
{
  # Claim `name` for `value`, then run `k ownerIdentity`.
  claimPolicyName =
    name: value: k:
    fx.bind fx.effects.state.get (
      state:
      let
        scope = state.currentScope;
        scopeParentMap = (state.scopeParent or (_: { })) null;
        bucketKey = "name:${name}";
        claimRegistry = (state.policyClaimsByName or (_: { })) null;
        claimsByScope = claimRegistry.${bucketKey} or { };
        claimResult = resolveClaim scopeParentMap scope claimsByScope value;
        inherit (claimResult) sameScopeEntries matchingClaim;
        parentStack = ((state.scopedIncludesChainSegments or (_: { })) null).${scope} or [ ];
        parentChainSegments = if parentStack == [ ] then [ ] else lib.last parentStack;
        # Taken before this claim is appended, so the first displaced claim
        # gets 1, the second 2, etc. — unique per claim, not just per parent.
        claimIndex = builtins.length sameScopeEntries;
        ownerIdentity =
          if matchingClaim != null then
            matchingClaim.identity
          else if sameScopeEntries == [ ] then
            name
          else
            identity.pathKey (parentChainSegments ++ [ "${name}#${toString claimIndex}" ]);
      in
      if matchingClaim != null then
        k ownerIdentity
      else
        fx.bind (fx.effects.state.modify (
          st:
          st
          // {
            policyClaimsByName =
              _:
              claimRegistry
              // {
                ${bucketKey} = claimsByScope // {
                  ${scope} = (claimsByScope.${scope} or [ ]) ++ [
                    {
                      inherit value;
                      identity = ownerIdentity;
                      inherit scope;
                    }
                  ];
                };
              };
          }
        )) (_: k ownerIdentity)
    );
}
