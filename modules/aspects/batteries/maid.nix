{
  den,
  inputs,
  lib,
  ...
}:
let
  inherit (den.lib.home-env) makeHomeEnv;

  result = makeHomeEnv {
    className = "maid";
    supportedOses = [ "nixos" ];
    optionPath = "nix-maid";
    getModule =
      { host, ... }:
      if inputs ? nix-maid then
        inputs.nix-maid."${host.class}Modules".default
      else
        throw "den: maid battery requires inputs.nix-maid — add nix-maid to your flake inputs or set den.hosts.<system>.<name>.nix-maid.module explicitly";
    forwardPathFn =
      { user, ... }:
      [
        "users"
        "users"
        user.userName
        "maid"
      ];
  };

  # This environment's policy records, den's channels by value (#694 §12).
  # Read by isDenChannel at this one key; `apply` ignores any definition, so
  # a config can't add a channel.
  channelPolicies = result.battery.includes ++ result.userDetect.includes;
in
{
  options.den.internal.channelPolicies.maid = lib.mkOption {
    internal = true;
    visible = false;
    type = lib.types.listOf lib.types.raw;
    default = channelPolicies;
    apply = _: channelPolicies;
  };

  config = {
    den.schema.host.imports = [ result.hostConf ];
    den.schema.host.includes = [ result.battery ];

    den.schema.user.includes = [ result.userDetect ];

    den.classes.maid.description = "nix-maid user environment";
  };
}
