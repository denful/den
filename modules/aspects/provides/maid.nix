{
  den,
  lib,
  inputs,
  ...
}:
let
  inherit (den.lib.home-env) makeHomeEnv;

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
  den.aspects = result.aspects;
  den.schema.host.imports = [ result.hostConf ];
  den.policies = result.policies;
  den.schema.host.policies = result.schemaPolicies;

  den.classes.maid.description = "nix-maid user environment";
}
