# DEPRECATED: scheduled for removal after first stable release post-fx-pipeline merge.
# Migration: remove provides from aspects; use policies for cross-entity routing.
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

  inherit (den.lib.aspects.fx.keyClassification) structuralKeysSet;

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

  inherit (den.lib.aspects.fx.contentUtil) unwrapContentValues;

  # Extract non-structural keys from an aspect result as class modules.
  extractClassModules =
    result:
    let
      allKeys = builtins.attrNames result;
      classKeys = builtins.filter (k: !(structuralKeysSet ? ${k})) allKeys;
    in
    map (k: {
      class = k;
      module = unwrapContentValues result.${k};
    }) classKeys;

  # to-hosts: fires for every host×user pair, delivers directly to host's nixos class.
  # Uses policy.provide for direct delivery — no tree walk, no duplicate emissions.
  mkToHostsPolicy =
    aspectName: key: value:
    {
      host,
      user,
      ...
    }:
    let
      result = applyProvide value { inherit host user; };
      classModules = extractClassModules result;
    in
    lib.warn
      "den: aspect '${aspectName}' uses provides.${key} — migrate to:\n  den.aspects.${aspectName}.policies.${key} = { host, user, ... }:\n    [ (policy.provide { class = \"<class>\"; module = { <config> }; }) ];"
      (map (cm: policy.provide cm) classModules);

  # to-users: fires for every host×user pair, delivers to user's homeManager class.
  # Uses policy.provide for direct cross-class delivery into homeManager.
  mkToUsersPolicy =
    aspectName: key: value:
    {
      host,
      user,
      ...
    }:
    let
      result = applyProvide value { inherit host user; };
      classModules = extractClassModules result;
    in
    lib.warn
      "den: aspect '${aspectName}' uses provides.${key} — migrate to:\n  den.aspects.${aspectName}.policies.${key} = { host, user, ... }:\n    [ (policy.provide { class = \"homeManager\"; module = { <config> }; }) ];"
      (map (cm: policy.provide cm) classModules);

  # Named target: fires only when entity name matches key.
  # Uses policy.provide for direct cross-class delivery into the target class.
  mkNamedTargetPolicy =
    aspectName: key: value:
    {
      host,
      user,
      ...
    }:
    let
      result = applyProvide value { inherit host user; };
      classModules = extractClassModules result;
    in
    lib.optionals (host.name == key || user.name == key) (
      lib.warn
        "den: aspect '${aspectName}' uses provides.${key} — migrate to:\n  den.aspects.${aspectName}.policies.${key} = { host, user, ... }:\n    lib.optional (host.name == \"${key}\" || user.name == \"${key}\")\n      (policy.provide { class = \"<class>\"; module = { <config> }; });"
        (map (cm: policy.provide cm) classModules)
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
