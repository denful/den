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

  # Two-hop collapsed to single policy: host → user with aspects.
  # Aspects are registered in den.aspects, attached via policy.aspects field.
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
    {
      aspects = {
        "${ctxName}-host-module" =
          { host }:
          {
            ${host.class}.imports = [ host.${optionPath}.module ];
          };

        "${ctxName}-user-forward" =
          { host, user }:
          den.provides.forward {
            each = lib.singleton true;
            fromClass = _: className;
            intoClass = _: host.class;
            intoPath = _: forwardPathFn { inherit host user; };
            fromAspect = _: den.lib.resolveEntity "user" { inherit host user; };
          };
      };

      hostConf = hostOptions {
        inherit
          className
          optionPath
          getModule
          ;
      };

      policies = {
        "host-to-${ctxName}-users" = {
          from = "host";
          to = "user";
          aspects = [
            "${ctxName}-host-module"
            "${ctxName}-user-forward"
          ];
          resolve =
            { host, ... }:
            let
              enabled = mkDetectHost {
                inherit className supportedOses optionPath;
              } { inherit host; };
            in
            if enabled != false && enabled != [ ] then mkIntoClassUsers className { inherit host; } else [ ];
        };
      };

      schemaPolicies = [ "host-to-${ctxName}-users" ];
    };

in
{
  inherit makeHomeEnv mkDetectHost mkIntoClassUsers;
}
