{
  lib,
  den,
  ...
}:
{ ctxFromHandlers }:
let
  fx = den.lib.fx;
  identity = den.lib.aspects.fx.identity;
  inherit (den.lib.aspects) isParametricWrapper isMeaningfulName isSubmoduleFn;

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
        identity = identity.pathKey (identity.aspectPath ref);
      }) rawExcludes;
      allConstraints = handleWithList ++ excludeList;
      owner = aspect.name or "<anon>";
    in
    fx.seq (map (c: fx.send "register-constraint" (c // { inherit owner; })) allConstraints);

  # --- Helpers moved from include.nix ---

  # Normalize a NixOS module function into an aspect attrset.
  normalizeModuleFn =
    child:
    den.lib.aspects.types.aspectType.merge
      [ (child.name or "<deferred>") ]
      [
        {
          file = "<deferred>";
          value = child;
        }
      ];

  wrapFunctorChild =
    child:
    let
      innerFn = child.__functor child;
      innerArgs = if builtins.isFunction innerFn then builtins.functionArgs innerFn else { };
    in
    if builtins.isFunction innerFn && isSubmoduleFn innerFn then
      normalizeModuleFn innerFn
    else
      child
      // {
        __fn =
          if child ? __args then
            child.__fn
          else if builtins.isFunction innerFn then
            innerFn
          else
            _: innerFn;
        __args =
          let
            explicit = child.__args or { };
          in
          if explicit != { } then explicit else innerArgs;
        includes = child.includes or [ ];
      };

  wrapBareFn =
    child:
    if isSubmoduleFn child then
      normalizeModuleFn child
    else
      {
        name = child.name or "<anon>";
        meta = child.meta or { };
        __fn = child;
        __args = lib.functionArgs child;
      };

  wrapChild =
    child:
    if lib.isFunction child then
      if builtins.isAttrs child && child ? name && child ? includes && builtins.isList child.includes then
        child
      else if builtins.isAttrs child then
        wrapFunctorChild child
      else
        wrapBareFn child
    else
      child;

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
      child
      // {
        meta = (child.meta or { }) // {
          constraintOwner = owner;
        };
      }
    else
      child;

  # --- Classifier-based emitIncludes ---

  # Fold includes, classifying each child and sending typed effects.
  # __skipNameAnon: when true, don't rename anonymous children (used by
  # emit-include handler for policy/self-provide callers that pass idx=null).
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
                    child =
                      if !__skipNameAnon && !(isMeaningfulName (withScope.name or "<anon>")) then
                        withScope // { name = nameAnon state idx (withScope.__ctxId or null); }
                      else
                        withScope;
                    isConditional = builtins.isAttrs child && child ? meta && child.meta ? guard;
                    isForward =
                      builtins.isAttrs child && child ? meta && builtins.isAttrs child.meta && child.meta ? __forward;
                    isParametric = (child.__args or { }) != { };
                  in
                  # 1. Dedup check
                  fx.bind (fx.send "check-dedup" child) (
                    { isDuplicate, dedupKey }:
                    if isDuplicate then
                      fx.pure [ ]
                    # 2. Forward
                    else if isForward then
                      fx.bind (fx.send "emit-forward" child.meta.__forward) (_: fx.pure [ ])
                    # 3. Conditional
                    else if isConditional then
                      fx.send "resolve-conditional" child
                    # 4. Constraint check → parametric or static
                    else
                      fx.bind
                        (fx.send "check-constraint" {
                          identity = identity.pathKey (identity.aspectPath child);
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
                        )
                  )
                );
              in
              fx.bind classifyAndSend (childResults: fx.pure (results ++ childResults))
            )
          );
    in
    go 0 (fx.pure [ ]);

  # --- Include constructors (unchanged) ---

  mkPositionalInclude =
    {
      innerFn,
      ctx,
      name,
      scopeHandlers,
      aspect,
      providerMeta,
    }:
    let
      resolved = innerFn ctx;
      resolvedArgs = if lib.isFunction resolved then lib.functionArgs resolved else { };
    in
    if lib.isFunction resolved && !builtins.isAttrs resolved then
      {
        inherit name;
        meta = providerMeta;
        __fn = resolved;
        __args = resolvedArgs;
      }
      // lib.optionalAttrs (scopeHandlers != null) { __parentScopeHandlers = scopeHandlers; }
      // lib.optionalAttrs (aspect ? __ctxId) { __parentCtxId = aspect.__ctxId; }
    else
      (if builtins.isAttrs resolved then resolved else { })
      // {
        inherit name;
        meta = providerMeta;
        includes = (if builtins.isAttrs resolved then resolved.includes or [ ] else [ ]);
      }
      // lib.optionalAttrs (aspect ? __ctxId) { __ctxId = aspect.__ctxId; };

  mkNamedInclude =
    {
      innerFn,
      providerVal,
      isParamWrapper,
      name,
      scopeHandlers,
      aspect,
      providerMeta,
      providerArgs,
    }:
    {
      inherit name;
      meta =
        providerMeta
        // (
          if isParamWrapper then
            builtins.removeAttrs (providerVal.meta or { }) [
              "provider"
              "selfProvide"
            ]
          else
            { }
        );
      __fn = if lib.isFunction innerFn then innerFn else _: providerVal;
      __args = providerArgs;
    }
    // lib.optionalAttrs (scopeHandlers != null) { __parentScopeHandlers = scopeHandlers; }
    // lib.optionalAttrs (aspect ? __ctxId) { __parentCtxId = aspect.__ctxId; };

  # Emit register-aspect-policy for each entry in aspect.policies.
  emitAspectPolicies =
    aspect:
    let
      policies = aspect.policies or { };
      aspectName = aspect.name or "<anon>";
      nodeIdentity = identity.pathKey (identity.aspectPath aspect);
    in
    if policies == { } then
      fx.pure null
    else
      fx.seq (
        lib.mapAttrsToList (
          policyName: policyFn:
          fx.send "register-aspect-policy" {
            name = "${aspectName}/${policyName}";
            fn = policyFn;
            ownerIdentity = nodeIdentity;
          }
        ) policies
      );

  emitSelfProvide =
    aspect:
    let
      name = aspect.name or "<anon>";
      provides = aspect.provides or { };
      providerVal = provides.${name};
      scopeHandlers = aspect.__scopeHandlers or null;
      ctx = ctxFromHandlers (aspect.__scopeHandlers or { });
      isParamWrapper = isParametricWrapper providerVal;
      innerFn =
        if isParamWrapper then
          providerVal.__fn
        else if builtins.isAttrs providerVal && providerVal ? __fn then
          providerVal.__fn
        else if builtins.isAttrs providerVal && lib.isFunction providerVal then
          providerVal.__functor providerVal
        else
          providerVal;
      providerArgs =
        if isParamWrapper then
          providerVal.__args
        else if lib.isFunction innerFn then
          lib.functionArgs innerFn
        else
          { };
    in
    if provides ? ${name} then
      let
        isPositionalFn = lib.isFunction innerFn && providerArgs == { };
        providerMeta = {
          provider = (aspect.meta.provider or [ ]) ++ [ name ];
          selfProvide = true;
        };
        shared = {
          inherit
            innerFn
            name
            scopeHandlers
            aspect
            providerMeta
            ;
        };
        include =
          if isPositionalFn then
            mkPositionalInclude (shared // { inherit ctx; })
          else
            mkNamedInclude (shared // { inherit providerVal isParamWrapper providerArgs; });
      in
      fx.send "emit-include" include
    else
      fx.pure [ ];

in
{
  inherit
    emitIncludes
    emitSelfProvide
    emitAspectPolicies
    registerConstraints
    ;
}
