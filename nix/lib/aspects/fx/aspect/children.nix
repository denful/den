# Walk an aspect's includes list — send each child through the resolve chain.
{
  lib,
  den,
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;
  inherit (import ./normalize.nix { inherit lib den; }) wrapChild isMeaningfulName;

  nameAnon =
    state: idx: ctxId:
    let
      chain = ((state.scopedIncludesChain or (_: { })) null).${state.currentScope} or [ ];
      parent = if chain == [ ] then "<root>" else lib.last chain;
      suffix = if ctxId != null then "/${ctxId}" else "";
    in
    "${parent}/<anon>:${toString idx}${suffix}";

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

  # Route a single __isPolicy value to the policy registry.
  registerPolicy =
    p:
    fx.send "register-aspect-policy" {
      inherit (p) name fn;
      ownerIdentity = identity.key p;
    };

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
          child =
            if !skipNameAnon && !(isMeaningfulName (withScope.name or "<anon>")) then
              withScope // { name = nameAnon state idx (withScope.__ctxId or null); }
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
      excludeList = map (ref: {
        type = "exclude";
        scope = "subtree";
        identity = if builtins.isAttrs ref && ref.__isPolicy or false then ref.name else identity.key ref;
      }) rawExcludes;
      allConstraints = handleWithList ++ excludeList;
      owner = aspect.name or "<anon>";
    in
    fx.seq (map (c: fx.send "register-constraint" (c // { inherit owner; })) allConstraints);
in
{
  inherit emitIncludes registerConstraints;
}
