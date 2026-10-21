{ denTest, ... }:
let
  mockMaidModule =
    { lib, ... }:
    {
      options.users.users = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.maid = lib.mkOption {
              type = lib.types.submoduleWith {
                modules = [
                  {
                    config._module.freeformType = lib.types.lazyAttrsOf lib.types.unspecified;
                  }
                ];
              };
              default = { };
            };
          }
        );
      };
    };
in
{
  flake.tests.maid-class = {

    test-maid-forwards-to-users = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux.classes = [ "maid" ];
          nix-maid.module = mockMaidModule;
        };

        den.aspects.tux.maid.description = "maid-tux";

        expr = igloo.users.users.tux.maid.description;
        expected = "maid-tux";
      }
    );

    test-maid-merges-with-nixos = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux.classes = [ "maid" ];
          nix-maid.module = mockMaidModule;
        };

        den.aspects.tux.maid.tags = [ "from-maid" ];
        den.aspects.igloo.nixos.users.users.tux.maid.tags = [ "from-nixos" ];

        expr = lib.sort (a: b: a < b) igloo.users.users.tux.maid.tags;
        expected = [
          "from-maid"
          "from-nixos"
        ];
      }
    );

    test-no-maid-without-maid-class = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          nix-maid.module = mockMaidModule;
        };

        expr = igloo ? users.tux.maid;
        expected = false;
      }
    );

  };
}
