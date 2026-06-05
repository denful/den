{ denTest, ... }:
{
  flake.tests.standalone-homes = {

    test-home-standalone-without-existing-host = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.homes.x86_64-linux."tux@igloo" = { };

        den.aspects.tux.homeManager = args: {
          home.keyboard.model = if args ? osConfig then "os-bound" else "standalone";
        };

        den.aspects.tux.policies.to-igloo =
          { home, ... }:
          lib.optional (home.hostName == "igloo") (include {
            homeManager.home.keyboard.layout = "enthium";
            includes = [
              (den.lib.perHome (
                { home }:
                {
                  homeManager.home.keyboard.variant = home.name;
                }
              ))
            ];
          });
        den.aspects.tux.includes = [
          den.provides.define-user
          den.aspects.tux.policies.to-igloo
        ];

        expr = {
          homeSchema = {
            inherit (den.homes.x86_64-linux."tux@igloo")
              userName
              hostName
              name
              host
              user
              ;
          };
          configuredUserName = config.flake.homeConfigurations."tux@igloo".config.home.username;
          keyboard = config.flake.homeConfigurations."tux@igloo".config.home.keyboard;
        };
        expected = {
          homeSchema.name = "tux";
          homeSchema.userName = "tux";
          homeSchema.hostName = "igloo";
          homeSchema.host = null;
          homeSchema.user = null;
          configuredUserName = "tux";
          keyboard.model = "standalone";
          keyboard.layout = "enthium";
          keyboard.variant = "tux";
          keyboard.options = [ ];
        };
      }
    );

  };
}
