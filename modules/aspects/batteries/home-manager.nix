{
  den,
  config,
  lib,
  inputs,
  ...
}:
let
  inherit (den.lib.home-env) makeHomeEnv mkDetectHost;

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

  # Bridge den.schema.hm-host includes into host resolution via policy.include.
  # Guarded by policy.when — only fires when the host has homeManager users.
  hmHostSchemaIncludes = config.den.schema.hm-host.includes or [ ];
  hasHmUsers =
    { host, ... }:
    mkDetectHost {
      className = "homeManager";
      optionPath = "home-manager";
    } { inherit host; };
  hmHostBridge = den.lib.policy.when hasHmUsers (
    den.lib.policy.mkPolicy "hm-host-schema" (
      _: map (inc: den.lib.policy.include inc) hmHostSchemaIncludes
    )
  );

in
{
  den.schema.host.imports = [ result.hostConf ];
  den.schema.host.includes = [
    result.battery
  ]
  ++ lib.optionals (hmHostSchemaIncludes != [ ]) [
    { includes = [ hmHostBridge ]; }
  ];

  den.classes.homeManager.description = "Home Manager user environment";
}
