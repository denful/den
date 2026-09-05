# Walk an aspect's includes list — send each child through the resolve chain.
{
  lib,
  den,
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;
  inherit (import ./normalize.nix { inherit lib den; }) wrapChild isMeaningfulName;

  nameIndexed =
    state: base: idx: ctxId:
    let
      chain = ((state.scopedIncludesChain or (_: { })) null).${state.currentScope} or [ ];
      parent = if chain == [ ] then "<root>" else lib.last chain;
      suffix = if ctxId != null then "/${ctxId}" else "";
    in
    "${parent}/${base}:${toString idx}${suffix}";

  nameAnon = state: nameIndexed state "<anon>";

  # Synthetic names like "<when>" repeat per constructor; index them so
  # siblings don't dedup-collide at the gate.
  inherit (den.lib.aspects) isSyntheticName;

  # Wrap a computation in chain-push/chain-pop of the given position. Takes
  # the segment list alone and derives the rendered string from it — a single
  # carrier for one fact, so the string can never name a different position
  # than the list it was rendered from.
  chainWrap =
    nodeSegments: shouldPush: comp:
    if shouldPush then
      fx.bind (fx.send "chain-push" {
        identity = identity.pathKey nodeSegments;
        segments = nodeSegments;
      }) (_: fx.bind comp (result: fx.bind (fx.send "chain-pop" null) (_: fx.pure result)))
    else
      comp;

  propagateScope =
    parentScopeHandlers: parentCtxId: child:
    child
    // lib.optionalAttrs (parentScopeHandlers != null && !(child ? __scopeHandlers)) {
      __scopeHandlers = parentScopeHandlers;
    }
    // lib.optionalAttrs (parentCtxId != null && !(child ? __ctxId)) {
      __ctxId = parentCtxId;
    };

  dedupAndDispatch =
    child:
    fx.send "resolve" {
      aspect = child;
      identity = identity.key child;
      ctx = { };
    };

  # Route a single __isPolicy value to the policy registry. A policy's bare
  # `name` is the identity every other consumer already relies on (excludes,
  # cross-scope fired-tracking, broadcast dedup) — changing it unconditionally
  # would fix the collision below at the cost of every one of those. So the
  # bare name stays the identity in the overwhelming common case (one
  # registration per name per scope), and only a genuine collision — a
  # second, DIFFERENT record claiming a name already taken IN THIS SCOPE —
  # gets displaced to a chain-qualified identity instead of silently
  # overwriting the first (scopedAspectPolicies merges by overwrite, one dict
  # per scope).
  #
  # Claims are bucketed by bare name and scoped by state.currentScope, not by
  # definition position (Task 4c's registry for aspects): traced empirically,
  # two aspects each declaring their own "policies.tools" merge at DIFFERENT
  # option paths — each aspect's own submodule eval bakes its own name into
  # `loc` — so a def-position bucket puts them in separate buckets and misses
  # the collision entirely, even though both still land in the SAME scope's
  # scopedAspectPolicies and one overwrites the other. Whole-value equality
  # within one scope is what actually tells "one shared policy referenced
  # twice" (O5, must merge into one identity) apart from "two distinct
  # same-named policies" (O4, must split); two different scopes never
  # collide in scopedAspectPolicies to begin with, so entries from another
  # scope are excluded from the comparison rather than forcing a needless
  # qualification.
  registerPolicy =
    p:
    fx.bind fx.effects.state.get (
      state:
      let
        scope = state.currentScope;
        bucketKey = "name:${p.name}";
        claimRegistry = (state.policyClaimsByName or (_: { })) null;
        claimedEntries = claimRegistry.${bucketKey} or [ ];
        sameScopeEntries = builtins.filter (e: e.scope == scope) claimedEntries;
        # Whole-record comparison, nothing projected out: a record differing
        # only in, say, an attached label must not be read as the same
        # registration as one that lacks it.
        matchingClaim = lib.findFirst (e: p == e.value) null sameScopeEntries;
        parentStack = ((state.scopedIncludesChainSegments or (_: { })) null).${scope} or [ ];
        parentChainSegments = if parentStack == [ ] then [ ] else lib.last parentStack;
        ownerIdentity =
          if matchingClaim != null then
            matchingClaim.identity
          else if sameScopeEntries == [ ] then
            p.name
          else
            identity.pathKey (parentChainSegments ++ [ p.name ]);
        registerEffect = fx.send "register-aspect-policy" {
          inherit (p) fn;
          inherit ownerIdentity;
        };
      in
      if matchingClaim != null then
        registerEffect
      else
        fx.bind (fx.effects.state.modify (
          st:
          st
          // {
            policyClaimsByName =
              _:
              claimRegistry
              // {
                ${bucketKey} = claimedEntries ++ [
                  {
                    value = p;
                    identity = ownerIdentity;
                    inherit scope;
                  }
                ];
              };
          }
        )) (_: registerEffect)
    );

  isPolicy = v: builtins.isAttrs v && v.__isPolicy or false;

  processInclude =
    {
      parentScopeHandlers,
      parentCtxId,
      skipNameAnon,
    }:
    idx: rawChild:
    # Route policy values to register-aspect-policy instead of aspect walk.
    if isPolicy rawChild then
      registerPolicy rawChild
    else if builtins.isList rawChild then
      let
        policyItems = builtins.filter isPolicy rawChild;
        nonPolicyItems = builtins.filter (item: !isPolicy item) rawChild;
        recurse = processInclude { inherit parentScopeHandlers parentCtxId skipNameAnon; };
      in
      fx.bind (fx.seq (map registerPolicy policyItems)) (
        _:
        if nonPolicyItems == [ ] then
          fx.pure [ ]
        else
          fx.seq (lib.imap0 (i: item: recurse (idx * 100 + i) item) nonPolicyItems)
      )
    else
      # Existing behavior: wrap and dispatch as aspect.
      let
        withScope = propagateScope parentScopeHandlers parentCtxId (wrapChild rawChild);
      in
      fx.bind fx.effects.state.get (
        state:
        let
          childName = withScope.name or "<anon>";
          # __walkStamped records that the name below was invented from walk
          # position, not authored — compile-static reads it to decide
          # whether filling meta.aspect-chain here would double-encode the
          # same position (once in the stamped name, once in the chain).
          # A marker set here, rather than a shape compile-static infers from
          # the name, can't be confused with an author's own name choice.
          child =
            if skipNameAnon then
              withScope
            else if !(isMeaningfulName childName) then
              withScope
              // {
                name = nameAnon state idx (withScope.__ctxId or null);
                __walkStamped = true;
              }
            else if isSyntheticName childName then
              withScope
              // {
                name = nameIndexed state childName idx (withScope.__ctxId or null);
                __walkStamped = true;
              }
            else
              withScope;
        in
        dedupAndDispatch child
      );

  emitIncludes =
    {
      __parentScopeHandlers ? null,
      __parentCtxId ? null,
      __skipNameAnon ? false,
    }:
    incs:
    let
      processOne = processInclude {
        parentScopeHandlers = __parentScopeHandlers;
        parentCtxId = __parentCtxId;
        skipNameAnon = __skipNameAnon;
      };
      len = builtins.length incs;
      go =
        idx: acc:
        if idx >= len then
          acc
        else
          go (idx + 1) (
            fx.bind acc (
              results:
              fx.bind (processOne idx (builtins.elemAt incs idx)) (
                childResults: fx.pure ([ childResults ] ++ results)
              )
            )
          );
    in
    fx.bind (go 0 (fx.pure [ ])) (
      revChunks: fx.pure (builtins.concatLists (lib.reverseList revChunks))
    );

  registerConstraints =
    aspect:
    let
      rawHandleWith = aspect.meta.handleWith or null;
      rawExcludes = aspect.excludes or [ ];
      handleWithList =
        if rawHandleWith == null then
          [ ]
        else if builtins.isList rawHandleWith then
          rawHandleWith
        else if builtins.isAttrs rawHandleWith then
          [ rawHandleWith ]
        else
          [ ];
      # Compute exclude identity, normalizing content wrappers that have
      # __aspectChain but no name (nested keys without _ prefix).
      excludeIdentity =
        ref:
        if builtins.isAttrs ref && ref.__isPolicy or false then
          ref.name
        else if builtins.isAttrs ref && ref ? __aspectChain && !(ref ? name) then
          let
            prov = ref.__aspectChain;
          in
          identity.key {
            name = if prov != [ ] then lib.last prov else "<anon>";
            meta.aspect-chain = if prov != [ ] then lib.init prov else [ ];
          }
        else
          identity.key ref;
      excludeList = map (ref: {
        type = "exclude";
        scope = "subtree";
        identity = excludeIdentity ref;
      }) rawExcludes;
      allConstraints = handleWithList ++ excludeList;
      owner = aspect.name or "<anon>";
    in
    fx.seq (map (c: fx.send "register-constraint" (c // { inherit owner; })) allConstraints);
in
{
  inherit emitIncludes registerConstraints chainWrap;
}
