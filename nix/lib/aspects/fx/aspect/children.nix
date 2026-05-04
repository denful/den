# Walk an aspect's includes list — classify each child and dispatch to handlers.
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

  excludeChild =
    child: owner: dedupKey:
    let
      tombstone = identity.tombstone child { excludedFrom = owner; };
    in
    fx.bind (fx.send "resolve-complete" tombstone) (
      _:
      if dedupKey == null then
        fx.pure [ tombstone ]
      else
        fx.bind (fx.send "include-unseen" dedupKey) (_: fx.pure [ tombstone ])
    );

  substituteChild =
    child: decision:
    let
      tombstone = identity.tombstone child {
        excludedFrom = decision.owner;
        replacedBy = decision.replacement.name or "<anon>";
      };
    in
    fx.bind (fx.send "resolve-complete" tombstone) (
      _:
      fx.bind (den.lib.aspects.fx.aspect.aspectToEffect decision.replacement) (
        resolved:
        fx.pure [
          tombstone
          resolved
        ]
      )
    );

  tagConstraintOwner =
    child: decision:
    let
      owner = decision.owner or null;
    in
    if owner != null then
      child // { meta = (child.meta or { }) // { constraintOwner = owner; }; }
    else
      child;

  # Dispatch a single child to the appropriate handler based on its shape.
  dispatchChild =
    child: dedupKey:
    let
      isConditional = builtins.isAttrs child && child ? meta && child.meta ? guard;
      isForward =
        builtins.isAttrs child && child ? meta && builtins.isAttrs child.meta && child.meta ? __forward;
      isParametric = (child.__args or { }) != { };
    in
    if isForward then
      fx.bind (fx.send "emit-forward" child.meta.__forward) (_: fx.pure [ ])
    else if isConditional then
      fx.send "resolve-conditional" child
    else
      fx.bind
        (fx.send "check-constraint" {
          identity = identity.key child;
          aspect = child;
        })
        (
          decision:
          if decision.action == "exclude" then
            excludeChild child decision.owner dedupKey
          else if decision.action == "substitute" then
            substituteChild child decision
          else
            let
              tagged = tagConstraintOwner child decision;
            in
            if isParametric then fx.send "resolve-parametric" tagged else fx.send "resolve-aspect" tagged
        );

  # Fold includes, classifying each child and sending typed effects.
  emitIncludes =
    {
      __parentScopeHandlers ? null,
      __parentCtxId ? null,
      __skipNameAnon ? false,
    }:
    incs:
    let
      len = builtins.length incs;
      go =
        idx: acc:
        if idx >= len then
          acc
        else
          go (idx + 1) (
            fx.bind acc (
              results:
              let
                rawChild = builtins.elemAt incs idx;
                wrapped = wrapChild rawChild;
                withScope =
                  wrapped
                  // lib.optionalAttrs (__parentScopeHandlers != null && !(wrapped ? __scopeHandlers)) {
                    __scopeHandlers = __parentScopeHandlers;
                  }
                  // lib.optionalAttrs (__parentCtxId != null && !(wrapped ? __ctxId)) {
                    __ctxId = __parentCtxId;
                  };
                classifyAndSend = fx.bind fx.effects.state.get (
                  state:
                  let
                    namedChild =
                      if !__skipNameAnon && !(isMeaningfulName (withScope.name or "<anon>")) then
                        withScope // { name = nameAnon state idx (withScope.__ctxId or null); }
                      else
                        withScope;
                  in
                  fx.bind (fx.send "check-dedup" namedChild) (
                    { isDuplicate, dedupKey }:
                    if isDuplicate then
                      fx.pure [ ]
                    else
                      dispatchChild namedChild dedupKey
                  )
                );
              in
              fx.bind classifyAndSend (childResults: fx.pure ([ childResults ] ++ results))
            )
          );
    in
    fx.bind (go 0 (fx.pure [ ])) (revChunks: fx.pure (builtins.concatLists (lib.reverseList revChunks)));

  registerConstraints =
    aspect:
    let
      rawHandleWith = aspect.meta.handleWith or null;
      rawExcludes = aspect.meta.excludes or [ ];
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
        identity = identity.key ref;
      }) rawExcludes;
      allConstraints = handleWithList ++ excludeList;
      owner = aspect.name or "<anon>";
    in
    fx.seq (map (c: fx.send "register-constraint" (c // { inherit owner; })) allConstraints);
in
{
  inherit emitIncludes registerConstraints;
}
