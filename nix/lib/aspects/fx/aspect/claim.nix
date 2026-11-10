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
      let
        # A record wrapping others (`policy.when`, `policy.for`,
        # `policy.strict`) is also found under each wrapped record's name, so
        # an exclude of the record reaches it whatever it was renamed to
        # (`den.policies.sw = policy.strict w`). A separate index: `w`'s own
        # bucket, which decides displacement, is untouched. Whether a wrap is
        # den's is decided where it is read (handlers/constraint.nix).
        wrappedNames =
          v:
          if builtins.isAttrs v && v ? __wraps then
            [ (v.__wraps.name or null) ] ++ wrappedNames v.__wraps
          else
            [ ];
        wrappedIndex =
          st: id:
          let
            names = builtins.filter (n: n != null && n != name) (wrappedNames value);
            all = (st.policyClaimsByWrapped or (_: { })) null;
            add =
              acc: n:
              acc
              // {
                "name:${n}" = (acc."name:${n}" or { }) // {
                  ${scope} = ((acc."name:${n}" or { }).${scope} or [ ]) ++ [
                    {
                      inherit value scope;
                      identity = id;
                    }
                  ];
                };
              };
          in
          if names == [ ] then { } else { policyClaimsByWrapped = _: builtins.foldl' add all names; };
      in
      if matchingClaim != null then
        k ownerIdentity
      else
        fx.bind (fx.effects.state.modify (
          st:
          st
          // wrappedIndex st ownerIdentity
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
