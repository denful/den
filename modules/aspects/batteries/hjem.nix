{
  den,
  inputs,
  lib,
  ...
}:
let
  inherit (den.lib.home-env) makeHomeEnv;

  result = makeHomeEnv {
    className = "hjem";
    optionPath = "hjem";
    getModule =
      { host, ... }:
      if inputs ? hjem then
        inputs.hjem."${host.class}Modules".default
      else
        throw "den: hjem battery requires inputs.hjem — add hjem to your flake inputs or set den.hosts.<system>.<name>.hjem.module explicitly";
    forwardPathFn =
      { user, ... }:
      [
        "hjem"
        "users"
        user.userName
      ];
  };

  # This environment's policy records, den's channels by value (#694 §12).
  # Read by isDenChannel at this one key; `apply` ignores any definition, so
  # a config can't add a channel.
  channelPolicies = result.battery.includes ++ result.userDetect.includes;
in
{
  options.den.internal.channelPolicies.hjem = lib.mkOption {
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

    den.classes.hjem.description = "Hjem user environment";
  };
}
