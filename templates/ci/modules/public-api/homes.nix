{ denTest, ... }:
{
  flake.tests.standalone-homes = {

    test-home-configuration-created = denTest (
      { den, config, ... }:
      {
        den.homes.x86_64-linux.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";

        expr = config.flake.homeConfigurations ? tux;
        expected = true;
      }
    );

    test-home-aspect-config-applied = denTest (
      { den, config, ... }:
      {
        den.homes.x86_64-linux.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.provides.define-user ];
        den.aspects.tux.homeManager.programs.fish.enable = true;

        expr = config.flake.homeConfigurations.tux.config.programs.fish.enable;
        expected = true;
      }
    );

    test-home-custom-username = denTest (
      { den, config, ... }:
      {
        den.homes.x86_64-linux.cam = {
          userName = "cameron";
        };
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.provides.define-user ];

        expr = config.flake.homeConfigurations.cam.config.home.username;
        expected = "cameron";
      }
    );

    test-ctx-home-applies-aspect = denTest (
      { den, config, ... }:
      {
        den.homes.x86_64-linux.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.provides.define-user ];
        den.schema.home.includes = [
          { homeManager.programs.vim.enable = true; }
        ];

        expr = config.flake.homeConfigurations.tux.config.programs.vim.enable;
        expected = true;
      }
    );

    test-home-with-user-and-host-automatic-osArgs = denTest (
      { den, config, ... }:
      {
        den.default.homeManager.home.stateVersion = "25.11";

        # When an standalone home has user@host and there exist such host
        den.homes.x86_64-linux."tux@igloo" = { };
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.nixos.networking.hostName = "blizzard";
        den.aspects.tux.includes = [ den.provides.define-user ];
        den.aspects.tux.homeManager =
          { osConfig, ... }:
          {
            home.keyboard.model = osConfig.networking.hostName;
          };

        expr = {
          homeSchema = {
            inherit (den.homes.x86_64-linux."tux@igloo")
              userName
              hostName
              name
              ;
          };
          configuredUserName = config.flake.homeConfigurations."tux@igloo".config.home.username;
          hasOsConfig = config.flake.homeConfigurations."tux@igloo".config.home.keyboard.model;
        };
        expected = {
          homeSchema.name = "tux"; # re-uses same aspect as hosted HM.
          homeSchema.userName = "tux";
          homeSchema.hostName = "igloo";
          configuredUserName = "tux";
          hasOsConfig = "blizzard";
        };
      }
    );

  };
}
