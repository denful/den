{
  den,
  config,
  lib,
  inputs,
  ...
}:
let
  # Where a home-manager user's config nests inside the enclosing host config.
  # Single source of truth for both the forward delivery target and the
  # den.classes.homeManager.hostPath the pipe layer resolves producers against.
  userHostPath = userName: [
    "home-manager"
    "users"
    userName
  ];
  result = den.lib.home-env.makeHomeEnv {
    className = "homeManager";
    ctxName = "hm";
    optionPath = "home-manager";
    getModule = { host, ... }: inputs.home-manager."${host.class}Modules".home-manager;
    forwardPathFn = { user, ... }: userHostPath user.userName;
    schemaIncludes = config.den.schema.hm-host.includes or [ ];
  };

  # This environment's policy records, den's channels by value (#694 §12).
  # Read by isDenChannel at this one key; `apply` ignores any definition, so
  # a config can't add a channel.
  channelPolicies = result.battery.includes ++ result.userDetect.includes;
in
{
  options.den.internal.channelPolicies.homeManager = lib.mkOption {
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

    den.classes.homeManager.description = "Home Manager user environment";
    # home-manager nests under its host; a member reaches the host config via osConfig.
    den.classes.homeManager.parentPath = userHostPath;
    den.classes.homeManager.parentArg = "osConfig";
  };
}
