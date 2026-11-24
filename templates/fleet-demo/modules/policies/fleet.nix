# Fleet topology and user-access policies.
#
# Wires the scope tree: flake -> fleet -> environment -> hosts -> users.
# Each environment groups its hosts as siblings for pipe.collect.
#
# Environment membership derived from den.schema.host.environment.
# Environment entities read from fleet.environments registry.
# Users are assigned to hosts before resolution, by one assignment policy
# over facts: a user's `groups` against what fleet.user-access grants the
# host's `environment` and the host itself.
{
  lib,
  den,
  config,
  ...
}:
let
  inherit (den.lib.policy) resolve;

  # Capture module-level config for use inside policies.
  # Policy functions receive entity context (host, user, etc.), NOT module args.
  # Destructuring `config` in the policy signature would fail resolveArgsSatisfied
  # since `config` is not an entity binding in the resolve context.
  accessByEnv = config.fleet.user-access.by-environment;
  accessByHost = config.fleet.user-access.by-host;
  environments = config.fleet.environments;

  grantedTo =
    host:
    (accessByEnv.${host.facts.environment} or { groups = [ ]; }).groups
    ++ (accessByHost.${host.name} or { groups = [ ]; }).groups;
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
    ) environments;

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

  # host -> users: every registry user whose groups the host's environment
  # or the host itself grants. Runs once per host, before resolution.
  den.policies.user-access = den.lib.policy.assign (
    { host, users }:
    builtins.attrNames (
      lib.filterAttrs (_: u: builtins.any (g: builtins.elem g (grantedTo host)) u.facts.groups) users
    )
  );

  den.schema.flake.includes = [ den.policies.to-fleet ];
  den.schema.fleet.includes = [ den.policies.fleet-to-envs ];
  den.schema.environment.includes = [ den.policies.env-to-hosts ];
  den.schema.host.includes = [ den.policies.user-access ];
}
