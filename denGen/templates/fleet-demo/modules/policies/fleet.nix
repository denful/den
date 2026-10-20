# Fleet topology and user-access policies.
#
# Wires the scope tree: flake -> fleet -> environment -> hosts -> users.
# Each environment groups its hosts as siblings for pipe.collect.
#
# Environment membership derived from den.schema.host.environment.
# Environment entities read from fleet.environments registry.
# User resolution driven by fleet.user-access group intersection.
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
  registry = config.den.users.registry;
  accessByEnv = config.fleet.user-access.by-environment;
  accessByHost = config.fleet.user-access.by-host;
  environments = config.fleet.environments;

  # Filter registry user names whose groups intersect the granted set.
  matchRegistryUsers =
    grantedGroups:
    lib.filter (name: builtins.any (g: lib.elem g grantedGroups) registry.${name}.groups) (
      builtins.attrNames registry
    );
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

  # host -> users (by environment): resolve registry users whose groups match.
  den.policies.env-users =
    { host, ... }:
    let
      grant = accessByEnv.${host.environment} or { groups = [ ]; };
      matched = matchRegistryUsers grant.groups;
    in
    map (name: resolve.to "user" { user = registry.${name}; }) matched;

  # host -> users (by host): resolve registry users by host-specific group match.
  den.policies.host-users =
    { host, ... }:
    let
      grant = accessByHost.${host.name} or { groups = [ ]; };
      matched = matchRegistryUsers grant.groups;
    in
    map (name: resolve.to "user" { user = registry.${name}; }) matched;

  den.schema.flake.includes = [ den.policies.to-fleet ];
  den.schema.fleet.includes = [ den.policies.fleet-to-envs ];
  den.schema.environment.includes = [ den.policies.env-to-hosts ];
  den.schema.host.includes = [
    den.policies.env-users
    den.policies.host-users
  ];
  den.schema.host.excludes = [ den.policies.host-to-users ];
}
