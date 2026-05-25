{
  den,
  config,
  lib,
  inputs,
  ...
}:
let
  result = den.lib.home-env.makeHomeEnv {
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
    schemaIncludes = config.den.schema.hm-host.includes or [ ];
  };

in
{
  den.schema.host.imports = [ result.hostConf ];
  den.schema.host.includes = [ result.battery ];

  den.schema.user.includes = [ result.userDetect ];

  den.classes.homeManager.description = "Home Manager user environment";
}
