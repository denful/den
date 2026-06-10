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
  inherit (den.lib.schemaUtil) schemaEntityKinds schemaEntityKindsSet;

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
            # Deliver to a user or home scope matching `key` by host- or
            # user-name. All entity args are optional so this fires at every
            # sibling kind (user AND home) — leaving any required entity arg
            # would restrict late-dispatch to that kind only, missing standalone
            # homes. `atDeliverableScope` keeps it inert at a bare host scope
            # (which fans out to its user scopes), and lets a standalone
            # `user@host` home match on its synthetic host identity.
            {
              host ? null,
              user ? null,
              home ? null,
              ...
            }:
            let
              result = applyProvide value { inherit host user; };
              atDeliverableScope = user != null || home != null;
              matches = (host != null && host.name == key) || (user != null && user.name == key);
            in
            lib.optionals (atDeliverableScope && matches) [
              (policy.include result)
            ]
          );
    in
    fx.send "register-aspect-policy" {
      name = "${aspectName}/${key}";
      fn = policyFn;
      ownerIdentity = nodeIdentity;
    };

  # Extract the inner function and args from a provider value.
  resolveProviderFn =
    providerVal:
    let
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
      args =
        if isParamWrapper then
          providerVal.__args
        else if lib.isFunction innerFn then
          lib.functionArgs innerFn
        else
          { };
    in
    {
      inherit innerFn args isParamWrapper;
    };

  # Tag an include with scope/ctx propagation attrs.
  tagScopeAttrs =
    aspect: scopeHandlers: attrs:
    attrs
    // lib.optionalAttrs (scopeHandlers != null) { __parentScopeHandlers = scopeHandlers; }
    // lib.optionalAttrs (aspect ? __ctxId) { __parentCtxId = aspect.__ctxId; };

  mkSelfProvideInclude =
    aspect: aspectName:
    let
      providerVal = (aspect.provides or { }).${aspectName};
      scopeHandlers = aspect.__scopeHandlers or null;
      ctx = ctxFromHandlers (aspect.__scopeHandlers or { });
      inherit (resolveProviderFn providerVal) innerFn args isParamWrapper;
      isPositionalFn = lib.isFunction innerFn && args == { };
      providerMeta = {
        provider = (aspect.meta.provider or [ ]) ++ [ aspectName ];
        selfProvide = true;
      };
    in
    if isPositionalFn then
      let
        resolved = innerFn ctx;
      in
      if lib.isFunction resolved && !builtins.isAttrs resolved then
        tagScopeAttrs aspect scopeHandlers {
          name = aspectName;
          meta = providerMeta;
          __fn = resolved;
          __args = lib.functionArgs resolved;
        }
      else
        (if builtins.isAttrs resolved then resolved else { })
        // {
          name = aspectName;
          meta = providerMeta;
          includes = if builtins.isAttrs resolved then resolved.includes or [ ] else [ ];
        }
        // lib.optionalAttrs (aspect ? __ctxId) { inherit (aspect) __ctxId; }
    else
      tagScopeAttrs aspect scopeHandlers {
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
        __args = args;
      };

  emitAspectPolicies =
    aspect:
    let
      aspectName = aspect.name or "<anon>";
      nodeIdentity = identity.key aspect;

      provides = aspect.provides or { };
      crossKeys = builtins.filter (k: k != aspectName) (builtins.attrNames provides);
      compatKeys = builtins.filter (k: !(schemaEntityKindsSet ? ${k})) crossKeys;
      allRegistrations = map (mkCrossPolicy aspectName nodeIdentity provides) compatKeys;

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
