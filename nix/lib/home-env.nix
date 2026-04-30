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
      hostModule =
        { host }:
        {
          ${host.class}.imports = [ host.${optionPath}.module ];
        };

      userForward =
        { host, user }:
        den.provides.forward {
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
            resolves = map (pair: den.lib.policy.resolve { user = pair.user; }) pairs;
            includes = [
              (den.lib.policy.include hostModule)
              (den.lib.policy.include userForward)
            ]
            ++ lib.optional (den.aspects ? os-user-class-fwd) (
              den.lib.policy.include den.aspects.os-user-class-fwd
            );
          in
          resolves ++ includes;
    in
    {
      battery = {
        policies."host-to-${ctxName}-users" = policyFn;
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
