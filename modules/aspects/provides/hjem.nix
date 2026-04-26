{
  den,
  lib,
  inputs,
  ...
}:
let
  inherit (den.lib.home-env) makeHomeEnv;

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
  den.policies = result.policies;
  den.schema.host.policies = result.schemaPolicies;

  den.classes.hjem.description = "Hjem user environment";
}
