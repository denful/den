{ denTest, ... }:
let
  mockWslModule =
    { lib, ... }:
    {
      options.wsl.defaultUser = lib.mkOption { type = lib.types.str; };
      options.wsl.enable = lib.mkOption { type = lib.types.bool; };
    };
in
{
  flake.tests.wsl-class = {

    test-wsl-forwards = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          wsl.enable = true;
          wsl.module = mockWslModule;
          users.tux = { };
        };

        den.aspects.tux.includes = [ den.provides.primary-user ];

        expr = {
          user = igloo.wsl.defaultUser;
          enabled = igloo.wsl.enable;
        };

        expected = {
          user = "tux";
          enabled = true;
        };
      }
    );

    test-wsl-from-parametric-include = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo = {
          wsl.enable = true;
          wsl.module = mockWslModule;
          users.tux = { };
        };

        den.aspects.igloo = {
          includes = [
            (
              { host, ... }:
              lib.optionalAttrs (host.class == "nixos") {
                wsl.defaultUser = "tux";
              }
            )
          ];
        };

        expr = igloo.wsl.defaultUser;
        expected = "tux";
      }
    );
  };
}
