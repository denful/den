{
  den,
  lib,
  inputs,
  ...
}:
let
  inherit (den.lib.home-env) makeHomeEnv mkDetectHost mkIntoClassUsers;

  result = makeHomeEnv {
    className = "hjem";
    optionPath = "hjem";
    getModule = { host, ... }: inputs.hjem."${host.class}Modules".default;
    forwardPathFn =
      { user, ... }:
      [
        "hjem"
        "users"
        user.userName
      ];
  };

in
{
  den.stages = result.stages;
  den.schema.host.imports = [ result.hostConf ];

  den.policies = {
    host-to-hjem-host = {
      from = "host";
      to = "hjem-host";
      resolve = mkDetectHost {
        className = "hjem";
        optionPath = "hjem";
      };
    };

    hjem-host-to-hjem-user = {
      from = "hjem-host";
      to = "hjem-user";
      resolve = mkIntoClassUsers "hjem";
    };
  };

  den.schema.host.policies = [
    "host-to-hjem-host"
    "hjem-host-to-hjem-user"
  ];
}
