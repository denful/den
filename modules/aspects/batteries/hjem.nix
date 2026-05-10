{
  den,
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
  den.schema.host.imports = [ result.hostConf ];
  den.schema.host.includes = [ result.battery ];

  den.classes.hjem.description = "Hjem user environment";
}
