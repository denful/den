{ denTest, ... }:
let
  mockHjemModule =
    { lib, ... }:
    {
      options.hjem.users = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submoduleWith {
            modules = [
              {
                config._module.freeformType = lib.types.lazyAttrsOf lib.types.unspecified;
              }
            ];
          }
        );
        default = { };
      };
    };
in
{
  flake.tests.hjem-class = {

    test-hjem-forwards-to-users = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux.classes = [ "hjem" ];
          hjem.module = mockHjemModule;
        };

        den.aspects.tux.hjem.theme = "nord";

        expr = igloo.hjem.users.tux.theme;
        expected = "nord";
      }
    );

    test-hjem-merges-with-nixos = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux.classes = [ "hjem" ];
          hjem.module = mockHjemModule;
        };

        den.aspects.tux.hjem.tags = [ "from-hjem" ];
        den.aspects.igloo.nixos.hjem.users.tux.tags = [ "from-nixos" ];

        expr = lib.sort (a: b: a < b) igloo.hjem.users.tux.tags;
        expected = [
          "from-hjem"
          "from-nixos"
        ];
      }
    );

    test-no-hjem-without-hjem-class = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          hjem.module = mockHjemModule;
        };

        expr = igloo ? hjem;
        expected = false;
      }
    );

  };
}
