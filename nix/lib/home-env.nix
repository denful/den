{
  den,
  lib,
  inputs,
  ...
}:
let
  host-has-user-with-class =
    host: class: builtins.any (user: lib.elem class user.classes) (lib.attrValues host.users);

  # Shared policy helpers for class-based batteries (home-manager, hjem, maid).
  # Used by both makeHomeEnv (internally) and battery policy declarations.
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
    lib.optional (isEnabled && isOsSupported && hostHasClass) { inherit host; };

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

  userEnvAspect =
    ctxName:
    { host, user, ... }:
    {
      includes = [
        (den.lib.resolveStage "${ctxName}-user" { inherit host user; })
        (den.lib.resolveStage "user" { inherit host user; })
      ];
    };

  forwardToHost =
    {
      className,
      ctxName,
      forwardPathFn,
    }:
    { host, user }:
    den.provides.forward {
      each = lib.singleton true;
      fromClass = _: className;
      intoClass = _: host.class;
      intoPath = _: forwardPathFn { inherit host user; };
      fromAspect = _: userEnvAspect ctxName;
    };

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
      stages = {
        "${ctxName}-host".provides."${ctxName}-host" =
          { host }:
          {
            ${host.class}.imports = [ host.${optionPath}.module ];
          };

        "${ctxName}-user".provides."${ctxName}-user" = forwardToHost {
          inherit className ctxName forwardPathFn;
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
        "host-to-${ctxName}-host" = {
          from = "host";
          to = "${ctxName}-host";
          resolve = mkDetectHost {
            inherit className supportedOses optionPath;
          };
          # Future: aspects = [ "${ctxName}-host" ] when stages are removed
        };
        "${ctxName}-host-to-${ctxName}-user" = {
          from = "${ctxName}-host";
          to = "${ctxName}-user";
          resolve = mkIntoClassUsers className;
          # Future: aspects = [ "${ctxName}-user" ] when stages are removed
        };
      };

      schemaPolicies = [
        "host-to-${ctxName}-host"
        "${ctxName}-host-to-${ctxName}-user"
      ];
    };

in
{
  inherit makeHomeEnv mkDetectHost mkIntoClassUsers;
}
