{ denTest, ... }:
{
  flake.tests.home-flat-form = {
    test-host-context-in-standalone-home = denTest (
      { den, config, ... }:
      {
        den.default.includes = [ den.provides.define-user ];

        den.homes.x86_64-linux."tux@igloo" = { };
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.nixos.networking.hostName = "igloo";
        den.aspects.tux.homeManager =
          { host, ... }:
          {
            home.sessionVariables.HOST_CLASS = host.class;
          };

        expr = config.flake.homeConfigurations."tux@igloo".config.home.sessionVariables.HOST_CLASS;
        expected = "nixos";
      }
    );

    test-mixed-den-and-module-args = denTest (
      { den, config, ... }:
      {
        den.default.includes = [ den.provides.define-user ];

        den.homes.x86_64-linux."tux@igloo" = { };
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.nixos.networking.hostName = "igloo";
        den.aspects.tux.homeManager =
          {
            host,
            pkgs,
            lib,
            ...
          }:
          lib.optionalAttrs (host.class != "darwin") {
            home.sessionVariables.HOST_CLASS = host.class;
            home.sessionVariables.SYSTEM = pkgs.system;
          };

        expr = config.flake.homeConfigurations."tux@igloo".config.home.sessionVariables;
        expected = {
          HOST_CLASS = "nixos";
          SYSTEM = "x86_64-linux";
        };
      }
    );
  };
}
