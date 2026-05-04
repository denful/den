# Aspect policy + self-provide emission.
# Registers aspect.policies entries and translates aspect.provides into
# policy effects (cross-entity) or direct includes (self-provide).
{
  lib,
  den,
}:
{ ctxFromHandlers }:
let
  inherit (den.lib) fx policy;
  inherit (den.lib.aspects.fx) identity;
  inherit (den.lib.aspects.fx.contentUtil) applyProvide;
  inherit (den.lib.aspects) isParametricWrapper;
  inherit (den.lib.schemaUtil) schemaEntityKinds;

  mkCrossPolicy =
    aspectName: nodeIdentity: provides: key:
    let
      value = provides.${key};
      policyFn =
        if key == "to-hosts" || key == "to-users" then
          (
            { host, user, ... }:
            let
              result = applyProvide value { inherit host user; };
            in
            [ (policy.include result) ]
          )
        else
          (
            { host, user, ... }:
            let
              result = applyProvide value { inherit host user; };
            in
            lib.optionals (host.name == key || user.name == key) [
              (policy.include result)
            ]
          );
    in
    fx.send "register-aspect-policy" {
      name = "${aspectName}/${key}";
      fn = policyFn;
      ownerIdentity = nodeIdentity;
    };

  mkSelfProvideInclude =
    aspect: aspectName:
    let
      provides = aspect.provides or { };
      providerVal = provides.${aspectName};
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
      isPositionalFn = lib.isFunction innerFn && providerArgs == { };
      providerMeta = {
        provider = (aspect.meta.provider or [ ]) ++ [ aspectName ];
        selfProvide = true;
      };
    in
    if isPositionalFn then
      let
        resolved = innerFn ctx;
        resolvedArgs = if lib.isFunction resolved then lib.functionArgs resolved else { };
      in
      if lib.isFunction resolved && !builtins.isAttrs resolved then
        {
          name = aspectName;
          meta = providerMeta;
          __fn = resolved;
          __args = resolvedArgs;
        }
        // lib.optionalAttrs (scopeHandlers != null) { __parentScopeHandlers = scopeHandlers; }
        // lib.optionalAttrs (aspect ? __ctxId) { __parentCtxId = aspect.__ctxId; }
      else
        (if builtins.isAttrs resolved then resolved else { })
        // {
          name = aspectName;
          meta = providerMeta;
          includes = if builtins.isAttrs resolved then resolved.includes or [ ] else [ ];
        }
        // lib.optionalAttrs (aspect ? __ctxId) { inherit (aspect) __ctxId; }
    else
      {
        name = aspectName;
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

  emitAspectPolicies =
    aspect:
    let
      aspectName = aspect.name or "<anon>";
      nodeIdentity = identity.key aspect;

      policies = aspect.policies or { };
      policyRegistrations = lib.mapAttrsToList (
        policyName: policyFn:
        fx.send "register-aspect-policy" {
          name = "${aspectName}/${policyName}";
          fn = policyFn;
          ownerIdentity = nodeIdentity;
        }
      ) policies;

      provides = aspect.provides or { };
      crossKeys = builtins.filter (k: k != aspectName) (builtins.attrNames provides);
      compatKeys = builtins.filter (k: !builtins.elem k schemaEntityKinds) crossKeys;
      crossRegistrations = map (mkCrossPolicy aspectName nodeIdentity provides) compatKeys;

      allRegistrations = policyRegistrations ++ crossRegistrations;

      hasSelfProvide = provides ? ${aspectName};
      selfProvide = mkSelfProvideInclude aspect aspectName;
    in
    if allRegistrations == [ ] && !hasSelfProvide then
      fx.pure [ ]
    else if allRegistrations == [ ] && hasSelfProvide then
      fx.send "emit-include" selfProvide
    else if !hasSelfProvide then
      fx.bind (fx.seq allRegistrations) (_: fx.pure [ ])
    else
      fx.bind (fx.seq allRegistrations) (_: fx.send "emit-include" selfProvide);
in
{
  inherit emitAspectPolicies;
}
