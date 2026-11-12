# The policy name claim, shared by registerPolicy (children.nix) and den's
# provides policies (provide.nix): every registration into the per-scope
# policy registry claims its name here first, so a second, different
# registration under a taken name is displaced to a chain-qualified identity
# instead of silently overwriting the first (O4), and the same registration
# seen again keeps its identity (O5). `value` is what tells them apart, by
# whole-value `==`, or the include site the record was written at (children.nix
# policySiteKey): a record built inside a parametric include is a new value in
# every copy of that include, and every copy is the same registration.
{ lib, den }:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;
  inherit (import ../handlers/constraint.nix { inherit lib den; }) resolveClaim;
in
rec {
  # Claim `name` for `value`, then run `k ownerIdentity`.
  claimPolicyName = claimPolicyNameAt null;

  # The same, for a record written at include `site` (null: no site).
  claimPolicyNameAt =
    site: name: value: k:
    fx.bind fx.effects.state.get (
      state:
      let
        scope = state.currentScope;
        scopeParentMap = (state.scopeParent or (_: { })) null;
        bucketKey = "name:${name}";
        claimRegistry = (state.policyClaimsByName or (_: { })) null;
        claimsByScope = claimRegistry.${bucketKey} or { };
        claimResult = resolveClaim scopeParentMap scope claimsByScope value;
        inherit (claimResult) sameScopeEntries;
        # A copy of a registration already made, from the same include for the
        # same bindings (children.nix policySiteKey).
        siteCopy =
          if claimResult.matchingClaim != null || site == null then
            null
          else
            lib.findFirst (e: (e.site or null) == site) null sameScopeEntries;
        matchingClaim = if siteCopy != null then siteCopy else claimResult.matchingClaim;
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
      # The registration it copies already fires for these bindings; a second
      # one would fire again, under the copy's own delivery keys.
      if siteCopy != null then
        fx.pure null
      else if matchingClaim != null then
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
                      inherit value site;
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
