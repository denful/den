{ denTest, lib, ... }:
{
  flake.tests.cross-context-forward = {

    test-resolve-other-host-context = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.hosts.x86_64-linux.iceberg = { };

        den.aspects.igloo.nixos.environment.sessionVariables.FROM_IGLOO = "yes";

        expr =
          let
            iglooCtx = den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; };
            resolved = den.lib.aspects.resolve "nixos" iglooCtx;
          in
          resolved ? imports;
        expected = true;
      }
    );

    test-entities-have-resolved = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.homes.x86_64-linux.cabin = { };

        expr = {
          host = den.hosts.x86_64-linux.igloo ? resolved;
          user = den.hosts.x86_64-linux.igloo.users.tux ? resolved;
          home = den.homes.x86_64-linux.cabin ? resolved;
        };
        expected = {
          host = true;
          user = true;
          home = true;
        };
      }
    );

    test-user-resolved-produces-aspect = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux =
          { host, user }:
          {
            nixos.environment.sessionVariables.USER_HOST = "${user.userName}@${host.hostName}";
          };

        expr =
          let
            user = den.hosts.x86_64-linux.igloo.users.tux;
            resolved = den.lib.aspects.resolve "nixos" user.resolved;
          in
          resolved ? imports;
        expected = true;
      }
    );

    # Cross-pipeline forward tests removed — require fleet-level scope (deferred).
    # See docs/superpowers/specs/2026-04-30-forward-route-unification.md

  };
}
