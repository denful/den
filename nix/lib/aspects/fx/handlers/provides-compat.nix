# Backwards-compatibility handler for main-era provides.X cross-provide patterns.
# Synthesizes aspect policies that replicate mutual-provider routing.
# Remove after migration period (see provides-removal spec).
{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  identity = den.lib.aspects.fx.identity;
  policy = den.lib.policy;

  schemaKinds = builtins.filter (n: den.schema.${n}.isEntity or false) (
    builtins.attrNames (den.schema or { })
  );

  # Mirror shape detection from emitSelfProvide in aspect.nix.
  applyProvide =
    value: ctx:
    if builtins.isAttrs value && value ? __fn then
      value.__fn ctx
    else if builtins.isAttrs value && value ? __functor then
      (value.__functor value) ctx
    else if lib.isFunction value then
      value ctx
    else
      value;

  # to-users / to-hosts: fires for every host×user pair.
  mkWildcardPolicy =
    aspectName: key: value:
    {
      host,
      user,
      ...
    }:
    let
      result = applyProvide value { inherit host user; };
    in
    [
      (policy.include (
        lib.warn "den: aspect '${aspectName}' uses provides.${key} — migrate to:\n  den.aspects.${aspectName}.policies.${key} = { host, user, ... }:\n    [ (policy.include { <config> }) ];" result
      ))
    ];

  # Named target: fires only when entity name matches key.
  mkNamedTargetPolicy =
    aspectName: key: value:
    {
      host,
      user,
      ...
    }:
    let
      result = applyProvide value { inherit host user; };
    in
    lib.optional (host.name == key || user.name == key) (
      policy.include (
        lib.warn "den: aspect '${aspectName}' uses provides.${key} — migrate to:\n  den.aspects.${aspectName}.policies.${key} = { host, user, ... }:\n    lib.optional (host.name == \"${key}\" || user.name == \"${key}\")\n      (policy.include { <config> });" result
      )
    );
in
{
  emitCrossProvideShims =
    aspect:
    let
      aspectName = aspect.name or "<anon>";
      provides = aspect.provides or { };
      crossKeys = builtins.filter (k: k != aspectName) (builtins.attrNames provides);
      compatKeys = builtins.filter (k: !builtins.elem k schemaKinds) crossKeys;
      nodeIdentity = identity.pathKey (identity.aspectPath aspect);
    in
    if compatKeys == [ ] then
      fx.pure null
    else
      fx.seq (
        map (
          key:
          let
            value = provides.${key};
            isWildcard = key == "to-users" || key == "to-hosts";
            policyFn =
              if isWildcard then
                mkWildcardPolicy aspectName key value
              else
                mkNamedTargetPolicy aspectName key value;
          in
          fx.send "register-aspect-policy" {
            name = "${aspectName}/compat:${key}";
            fn = policyFn;
            ownerIdentity = nodeIdentity;
          }
        ) compatKeys
      );
}
