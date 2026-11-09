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

  # The user → host half of a cross-entity provide, delivered by the
  # mutual-provider battery. The provided aspect is included at the user scope
  # inside a wrapper named after its provider (handlers/class-collector.nix
  # records what is emitted under it), and a route moves exactly that content,
  # folded in the user's own bucket, to the host. It is not resolved again, so
  # pipe values and the user's context bind as for any user content.
  provenanceMarker = "den-provides-to-host=";
  providedInclude =
    token: result:
    policy.include {
      name = "${provenanceMarker}${token}";
      includes = [ result ];
    };
  hostDelivery =
    token: ctx: host: user:
    let
      # A user the host already accepts through user-aspects delivers its whole
      # host-class bucket, this include's copy with it; delivering the provided
      # aspect as well would land it twice.
      viaUserAspects = den.lib.acceptance.acceptsExplicitly ctx host user;
      # Accepted only through user-aspects' transition default: the bucket
      # still reaches the host whole, so the route stands down, recorded for
      # the migration warning (#694).
      viaDefaultUserAspects = !viaUserAspects && den.lib.acceptance.accepts ctx host user;
      explicit = ctx ? ${den.lib.acceptance.mutualProviderKey host};
      byDefault = ctx ? ${den.lib.acceptance.mutualProviderDefaultKey host};
    in
    lib.optional
      (host ? class && (ctx.home or null) == null && (explicit || byDefault) && !viaUserAspects)
      (
        policy.route {
          fromClass = host.class;
          intoClass = host.class;
          receiver = host;
          __fromProvenance = token;
          # Made only by mutual-provider's transition default: the migration
          # warning lists what it delivers.
          __transitionDefault = !explicit;
          __standDown = viaDefaultUserAspects;
        }
      );

  mkCrossPolicy =
    nodeIdentity: provides: key:
    let
      value = provides.${key};
      # Unique per registration: the registry key (handlers/policy.nix).
      token = "${nodeIdentity}/${key}";
      policyFn =
        if key == "to-users" then
          (
            { host, user, ... }:
            let
              result = applyProvide value { inherit host user; };
            in
            [ (policy.include result) ]
          )
        else if key == "to-hosts" then
          (
            { host, user, ... }@ctx:
            let
              result = applyProvide value { inherit host user; };
            in
            [ (providedInclude token result) ] ++ hostDelivery token ctx host user
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
            }@ctx:
            let
              result = applyProvide value { inherit host user; };
              atDeliverableScope = user != null || home != null;
              matches = (host != null && host.name == key) || (user != null && user.name == key);
              toHost = host != null && user != null && host.name == key;
            in
            lib.optionals (atDeliverableScope && matches) (
              [ (if toHost then providedInclude token result else policy.include result) ]
              ++ lib.optionals toHost (hostDelivery token ctx host user)
            )
          );
    in
    fx.send "register-aspect-policy" {
      fn = policyFn;
      ownerIdentity = nodeIdentity;
      label = key;
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
        aspect-chain = identity.ownChain aspect ++ [ aspectName ];
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
                "aspect-chain"
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
      # Every merged aspect carries a synthetic `__functor` on `provides`; it is
      # pipeline machinery, not a delivery target. Registering it produced one
      # inert policy per aspect that re-dispatched on every iteration.
      compatKeys = builtins.filter (
        k: !(schemaEntityKindsSet ? ${k}) && !(lib.hasPrefix "__" k)
      ) crossKeys;
      allRegistrations = map (mkCrossPolicy nodeIdentity provides) compatKeys;

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
