{ denTest, ... }:
{
  flake.tests.stages = {

    # Behavior set on den.default appears in the resolved NixOS config.
    test-stage-default-nixos = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.nixos.users.users.tux.description = "from-default-stage";

        expr = igloo.users.users.tux.description;
        expected = "from-default-stage";
      }
    );

    # den.default carries both values:
    # both contribute to the resolved NixOS config without clobbering each other.
    test-stage-default-coexists-with-ctx = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.nixos.networking.hostName = "from-ctx-default";
        den.default.nixos.users.users.tux.description = "from-default-stage";

        expr = [
          igloo.networking.hostName
          igloo.users.users.tux.description
        ];
        expected = [
          "from-ctx-default"
          "from-default-stage"
        ];
      }
    );

    # Behavior set on den.schema.user appears in the resolved NixOS config
    # for each user (user entity kind is reached from host via policies).
    test-stage-user-nixos = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.user.includes = [
          { nixos.users.users.tux.description = "from-user-stage"; }
        ];

        expr = igloo.users.users.tux.description;
        expected = "from-user-stage";
      }
    );

    # Bare function sugar: den.schema.greet = { hello }: ...
    # is equivalent to den.schema.greet.provides.greet = { hello }: ...
    test-stage-function-sugar = denTest (
      { den, funnyNames, ... }:
      {
        den.schema.greet.includes = [
          (
            { hello }:
            {
              funny.names = [ hello ];
            }
          )
        ];

        expr = funnyNames (den.lib.resolveEntity "greet" { hello = "world"; });
        expected = [ "world" ];
      }
    );

  };
}
