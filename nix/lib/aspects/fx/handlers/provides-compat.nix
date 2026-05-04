# Compatibility shim for provides.to-users, provides.to-hosts, and provides.<name>.
# Translates legacy provides patterns into policy.include effects — the pipeline
# handles include walking, parametric resolution, class extraction, and dedup.
# Reserved keyword: provides.to-users / provides.to-hosts remain supported.
{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  identity = den.lib.aspects.fx.identity;
  policy = den.lib.policy;

  schemaKinds = den.lib.schemaUtil.schemaEntityKinds;

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

  # to-hosts: fires for every host×user pair, includes resolved content at current scope.
  mkToHostsPolicy =
    aspectName: key: value:
    {
      host,
      user,
      ...
    }:
    let
      result = applyProvide value { inherit host user; };
    in
    lib.warn
      "den: aspect '${aspectName}' uses provides.${key} — migrate to:\n  den.aspects.${aspectName}.policies.${key} = { host, user, ... }:\n    [ (policy.include { <config> }) ];"
      [ (policy.include result) ];

  # to-users: fires for every host×user pair, includes resolved content at user scope.
  mkToUsersPolicy =
    aspectName: key: value:
    {
      host,
      user,
      ...
    }:
    let
      result = applyProvide value { inherit host user; };
    in
    lib.warn
      "den: aspect '${aspectName}' uses provides.${key} — migrate to:\n  den.aspects.${aspectName}.policies.${key} = { host, user, ... }:\n    [ (policy.include { <config> }) ];"
      [ (policy.include result) ];

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
    lib.optionals (host.name == key || user.name == key) (
      lib.warn
        "den: aspect '${aspectName}' uses provides.${key} — migrate to:\n  den.aspects.${aspectName}.policies.${key} = { host, user, ... }:\n    lib.optional (host.name == \"${key}\" || user.name == \"${key}\")\n      (policy.include { <config> });"
        [ (policy.include result) ]
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
            policyFn =
              if key == "to-hosts" then
                mkToHostsPolicy aspectName key value
              else if key == "to-users" then
                mkToUsersPolicy aspectName key value
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
