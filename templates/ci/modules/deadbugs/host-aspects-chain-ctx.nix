# Regression: the host-aspects battery re-resolves the host aspect tree for a
# user's classes (e.g. homeManager) in an isolated sub-pipeline.  It seeded that
# re-resolution with only { host, user }, dropping the resolution-chain context
# the host scope actually carries (e.g. a parent `environment`).  A parametric
# host quirk emit `{ environment, host, ... }: ...` was then stranded as a raw
# function at the {host,user} projection scope, crashing any homeManager
# consumer that read the pipe ("expected a set but found a function").
#
# Fix: from-host threads the ambient resolution-chain entity bindings into the
# re-resolution, so parametric host aspects bind the same args they would at the
# host scope.
{ denTest, lib, ... }:
{
  flake.tests.host-aspects-chain-ctx = {

    test-parametric-host-quirk-survives-home-projection = denTest (
      {
        den,
        tuxHm,
        lib,
        ...
      }:
      {
        # environment as a parent entity of host (mirrors a fleet topology).
        den.schema.environment.isEntity = true;
        den.schema.host.parent = "environment";

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.quirks.host-addrs.description = "Host address entries";

        # Walk flake -> environment -> host, injecting `environment` into the
        # host scope context.  Replaces the default per-system host walking.
        den.policies.to-env = _: [
          (den.lib.policy.resolve.to "environment" {
            environment = {
              name = "prod";
              domain = "example.com";
            };
          })
        ];
        den.policies.env-to-hosts =
          { environment, ... }:
          lib.concatMap (
            system:
            lib.concatMap (
              hostName:
              let
                host = den.hosts.${system}.${hostName};
              in
              [
                (den.lib.policy.resolve.to "host" { inherit host; })
                (den.lib.policy.instantiate host)
              ]
            ) (builtins.attrNames (den.hosts.${system} or { }))
          ) (builtins.attrNames (den.hosts or { }));

        den.schema.flake.includes = [ den.policies.to-env ];
        den.schema.environment.includes = [ den.policies.env-to-hosts ];
        den.schema.flake-system.excludes = [
          den.policies.system-to-os-outputs
          den.policies.system-to-hm-outputs
        ];

        # Host aspect tree: a parametric host-addrs emit requiring `environment`
        # (a host-only ctx key), consumed by a homeManager aspect projected onto
        # the user via the host-aspects battery.
        den.aspects.igloo.includes = [
          den.aspects.net-hosts
          den.aspects.ssh-home
        ];
        den.aspects.net-hosts.host-addrs =
          { environment, host, ... }:
          {
            hostname = host.name;
            domain = environment.domain;
          };
        den.aspects.ssh-home.homeManager =
          {
            host-addrs,
            lib,
            ...
          }:
          {
            home.sessionVariables.SSH_HOSTS = lib.concatMapStringsSep "," (
              e: "${e.hostname}.${e.domain}"
            ) host-addrs;
          };

        den.aspects.tux.includes = [ den._.host-aspects ];

        expr = tuxHm.home.sessionVariables.SSH_HOSTS;
        expected = "igloo.example.com";
      }
    );
  };
}
