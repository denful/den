{
  den,
  lib,
  inputs,
  ...
}:
let
  inherit (den.lib.home-env) makeHomeEnv;

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
  den.policies = result.policies;
  den.schema.host.policies = result.schemaPolicies;

  den.schema.classes.homeManager.description = "Home Manager user environment";
  den._classNames.homeManager = true;
}
