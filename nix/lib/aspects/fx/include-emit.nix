{
  lib,
  den,
  ...
}:
{ ctxFromHandlers }:
let
  fx = den.lib.fx;
  identity = den.lib.aspects.fx.identity;
  inherit (den.lib.aspects) isParametricWrapper;

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

  # Fold includes through emit-include effects, tagging each with its
  # positional index and parent __scopeHandlers so the handler
  # can derive stable identities and propagate context to children.
  emitIncludes =
    {
      __parentScopeHandlers ? null,
      __parentCtxId ? null,
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
              fx.bind (fx.send "emit-include" (
                {
                  child = builtins.elemAt incs idx;
                  inherit idx;
                }
                // lib.optionalAttrs (__parentScopeHandlers != null) { inherit __parentScopeHandlers; }
                // lib.optionalAttrs (__parentCtxId != null) { inherit __parentCtxId; }
              )) (childResults: fx.pure (results ++ childResults))
            )
          );
    in
    go 0 (fx.pure [ ]);

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
  # Each policy is stored with ownerIdentity for exclusion rollback.
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
