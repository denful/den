{
  den,
  lib,
  inputs,
  ...
}:
let
  host-has-user-with-class =
    host: class: builtins.any (user: lib.elem class user.classes) (lib.attrValues host.users);

  mkDetectHost =
    {
      className,
      supportedOses ? [
        "nixos"
        "darwin"
      ],
      optionPath,
    }:
    { host, ... }:
    let
      isOsSupported = builtins.elem host.class supportedOses;
      isEnabled = (host.${optionPath} or { }).enable or false;
      hostHasClass = host-has-user-with-class host className;
    in
    isEnabled && isOsSupported && hostHasClass;

  mkIntoClassUsers =
    className:
    { host, ... }:
    map (user: { inherit host user; }) (
      lib.filter (u: lib.elem className u.classes) (lib.attrValues host.users)
    );

  hostOptions =
    {
      className,
      optionPath,
      getModule,
    }:
    { host, ... }:
    {
      options.${optionPath} = {
        enable = lib.mkOption {
          type = lib.types.bool;
          defaultText = lib.literalExpression "host-has-user-with-class host className";
          default = host-has-user-with-class host className;
        };
        module = lib.mkOption {
          type = lib.types.deferredModule;
          defaultText = lib.literalExpression "getModule { inherit host inputs; }";
          default = getModule { inherit host inputs; };
        };
      };
    };

  # Self-contained battery: host → user routing via aspect-included policy.
  # The battery is an aspect with policies — include it in den.schema.host.includes
  # and its policy fires during host resolution without separate den.policies registration.
  makeHomeEnv =
    {
      className,
      ctxName ? className,
      supportedOses ? [
        "nixos"
        "darwin"
      ],
      optionPath,
      getModule,
      forwardPathFn,
    }:
    let
      # Keyed module wrapper: the NixOS module system deduplicates imports
      # with the same `key`, so this fires once even when included from
      # multiple user entity resolves.
      hostModule =
        { host }:
        {
          ${host.class}.imports = [
            {
              key = "den:${optionPath}-host-module";
              imports = [ host.${optionPath}.module ];
            }
          ];
        };

      userForward =
        { host, user }:
        den.batteries.forward {
          each = lib.singleton true;
          fromClass = _: className;
          intoClass = _: host.class;
          intoPath = _: forwardPathFn { inherit host user; };
          fromAspect = _: den.lib.resolveEntity "user" { inherit host user; };
        };

      policyFn =
        { host, ... }:
        let
          enabled = mkDetectHost {
            inherit className supportedOses optionPath;
          } { inherit host; };
        in
        if !enabled then
          [ ]
        else
          let
            pairs = mkIntoClassUsers className { inherit host; };
            resolves = map (
              pair: den.lib.policy.resolve.withIncludes [ userForward ] { user = pair.user; }
            ) pairs;
            rootIncludes = [
              (den.lib.policy.include hostModule)
            ]
            ++ lib.optional (den.aspects ? os-user-class-fwd) (
              den.lib.policy.include den.aspects.os-user-class-fwd
            );
          in
          resolves ++ rootIncludes;
    in
    {
      battery = {
        policies."host-to-${ctxName}-users" = policyFn;
        includes = [
          {
            __isPolicy = true;
            name = "host-to-${ctxName}-users";
            fn = policyFn;
          }
        ];
      };

      hostConf = hostOptions {
        inherit
          className
          optionPath
          getModule
          ;
      };

    };

in
{
  inherit makeHomeEnv mkDetectHost mkIntoClassUsers;
}
