# Regression: schema.hm-host crashes when a standalone home exists alongside
# hosts with HM users.  The hmHostBridge policy's predicate (hasHmUsers)
# destructures { host, ... } but policy.when lost the arg signature, causing
# the policy to fire in contexts without host.
{ denTest, ... }:
{
  flake.tests.hm-host-standalone-crash = {

    # Core bug: standalone home + hm-host schema → crash
    test-hm-host-with-standalone-home = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.homes.x86_64-linux.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";

        den.schema.hm-host.includes = [
          { nixos.home-manager.useGlobalPkgs = true; }
        ];

        expr = igloo.home-manager.useGlobalPkgs;
        expected = true;
      }
    );

    # Standalone home should still resolve independently
    test-standalone-home-unaffected = denTest (
      {
        config,
        den,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.homes.x86_64-linux.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.provides.define-user ];

        den.schema.hm-host.includes = [
          { nixos.home-manager.useGlobalPkgs = true; }
        ];
        den.schema.home.includes = [
          { homeManager.programs.home-manager.enable = true; }
        ];

        expr = config.flake.homeConfigurations.tux.config.programs.home-manager.enable;
        expected = true;
      }
    );

  };
}
