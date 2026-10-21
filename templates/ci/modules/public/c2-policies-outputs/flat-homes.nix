{ denTest, ... }:
{
  flake.tests.flat-homes = {
    test-flat-home-two-level-shape = denTest (
      { den, ... }:
      {
        den.homes."tux@igloo" = {
          system = "x86_64-linux";
        };

        expr = builtins.attrNames den.homes;
        expected = [ "x86_64-linux" ];
      }
    );

    test-flat-home-name-parsing = denTest (
      { den, ... }:
      {
        den.homes."tux@igloo" = {
          system = "x86_64-linux";
        };

        expr = {
          inherit (den.homes.x86_64-linux."tux@igloo")
            name
            userName
            hostName
            system
            ;
        };
        expected = {
          # `name` is the REGISTRY KEY, which is what identifies the home;
          # `userName` is the user it configures. The two are different
          # questions, and a home keyed `user@host` answers them differently.
          name = "tux@igloo";
          userName = "tux";
          hostName = "igloo";
          system = "x86_64-linux";
        };
      }
    );

    # What ASPECT CONTENT sees, as opposed to what the instance reports above.
    # `home.name` is the registry key at both, so a policy or class module
    # keyed on it identifies the home; `home.userName` is the user it
    # configures. Read through a class module rather than off the instance,
    # because that is the surface a user's aspects actually consume.
    test-flat-home-name-in-aspect-content = denTest (
      { den, config, ... }:
      {
        den.homes.x86_64-linux."tux@igloo" = { };
        den.aspects.tux.homeManager =
          { home, ... }:
          {
            home = {
              username = "tux";
              homeDirectory = "/home/tux";
              stateVersion = "25.05";
              sessionVariables = {
                SAW_NAME = home.name;
                SAW_USERNAME = home.userName;
              };
            };
          };

        expr =
          let
            vars = config.flake.homeConfigurations."tux@igloo".config.home.sessionVariables;
          in
          {
            inherit (vars) SAW_NAME SAW_USERNAME;
          };
        expected = {
          SAW_NAME = "tux@igloo";
          SAW_USERNAME = "tux";
        };
      }
    );

    test-flat-home-coexists-with-legacy = denTest (
      { den, ... }:
      {
        den.homes.x86_64-linux.legacy-home = { };
        den.homes."flat-home" = {
          system = "x86_64-linux";
        };

        expr = builtins.sort (a: b: a < b) (builtins.attrNames den.homes.x86_64-linux);
        expected = [
          "flat-home"
          "legacy-home"
        ];
      }
    );

    test-flat-home-cross-entity-host-lookup = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.homes."tux@igloo" = {
          system = "x86_64-linux";
        };

        den.aspects.igloo.nixos.networking.hostName = "igloo";
        den.aspects.tux.includes = [ den.provides.define-user ];
        den.aspects.tux.homeManager =
          { osConfig, ... }:
          {
            home.keyboard.model = osConfig.networking.hostName;
          };

        expr = config.flake.homeConfigurations."tux@igloo".config.home.keyboard.model;
        expected = "igloo";
      }
    );

    test-flat-home-output = denTest (
      { den, config, ... }:
      {
        den.homes."tux" = {
          system = "x86_64-linux";
        };
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.provides.define-user ];
        den.aspects.tux.homeManager.programs.fish.enable = true;

        expr = config.flake.homeConfigurations.tux.config.programs.fish.enable;
        expected = true;
      }
    );
  };
}
