{
  den,
  lib,
  inputs,
  ...
}:
let
  inherit (den.lib.home-env) makeHomeEnv mkDetectHost mkIntoClassUsers;

  result = makeHomeEnv {
    className = "maid";
    supportedOses = [ "nixos" ];
    optionPath = "nix-maid";
    getModule = { host, ... }: inputs.nix-maid."${host.class}Modules".default;
    forwardPathFn =
      { user, ... }:
      [
        "users"
        "users"
        user.userName
        "maid"
      ];
  };

in
{
  den.stages = result.stages;
  den.schema.host.imports = [ result.hostConf ];

  den.policies = {
    host-to-maid-host = {
      from = "host";
      to = "maid-host";
      resolve = mkDetectHost {
        className = "maid";
        supportedOses = [ "nixos" ];
        optionPath = "nix-maid";
      };
    };

    maid-host-to-maid-user = {
      from = "maid-host";
      to = "maid-user";
      resolve = mkIntoClassUsers "maid";
    };
  };

  den.schema.host.policies = [
    "host-to-maid-host"
    "maid-host-to-maid-user"
  ];
}
