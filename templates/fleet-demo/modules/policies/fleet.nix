# Fleet topology policies.
#
# Wires the scope tree: flake -> fleet -> environment -> hosts.
# Each environment groups its hosts as siblings for pipe.collect.
#
# Environment membership derived from den.schema.host.environment.
# Environment entities read from fleet.environments registry.
{
  lib,
  den,
  config,
  ...
}:
let
  inherit (den.lib.policy) resolve;
in
{
  # flake -> fleet: single fleet entity.
  den.policies.to-fleet = _: [
    (resolve.to "fleet" {
      fleet = {
        name = "fleet";
      };
    })
  ];

  # fleet -> environments: fan out per registered environment.
  den.policies.fleet-to-envs =
    { fleet, ... }:
    lib.mapAttrsToList (
      _: env:
      resolve.to "environment" {
        environment = env;
      }
    ) config.fleet.environments;

  # environment -> hosts: walk hosts whose environment matches.
  # Guard: only fire at environment scope (not at host scopes which inherit environment).
  den.policies.env-to-hosts =
    { environment, ... }:
    lib.concatMap (
      system:
      lib.concatMap (
        hostName:
        let
          hostCfg = den.hosts.${system}.${hostName};
        in
        lib.optionals ((hostCfg.environment or "default") == environment.name && hostCfg.intoAttr != [ ]) [
          (resolve.to "host" { host = hostCfg; })
          (den.lib.policy.instantiate hostCfg)
        ]
      ) (builtins.attrNames (den.hosts.${system} or { }))
    ) (builtins.attrNames (den.hosts or { }));

  den.schema.flake.includes = [ den.policies.to-fleet ];
  den.schema.fleet.includes = [ den.policies.fleet-to-envs ];
  den.schema.environment.includes = [ den.policies.env-to-hosts ];
}
