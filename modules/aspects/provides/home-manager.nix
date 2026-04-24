{
  den,
  lib,
  inputs,
  ...
}:
let
  inherit (den.lib.home-env) makeHomeEnv mkDetectHost mkIntoClassUsers;

  result = makeHomeEnv {
    className = "homeManager";
    ctxName = "hm";
    optionPath = "home-manager";
    getModule = { host, ... }: inputs.home-manager."${host.class}Modules".home-manager;
    forwardPathFn =
      { user, ... }:
      [
        "home-manager"
        "users"
        user.userName
      ];
  };

in
{
  den.stages = result.stages // {
    home.provides.home = { home }: home.aspect;
  };
  den.schema.host.imports = [ result.hostConf ];

  den.policies = {
    host-to-hm-host = {
      from = "host";
      to = "hm-host";
      resolve = mkDetectHost {
        className = "homeManager";
        optionPath = "home-manager";
      };
    };

    hm-host-to-hm-user = {
      from = "hm-host";
      to = "hm-user";
      resolve = mkIntoClassUsers "homeManager";
    };
  };

  den.schema.host.policies = [
    "host-to-hm-host"
    "hm-host-to-hm-user"
  ];
}
