# See https://github.com/denful/den/issues/254
{ denTest, ... }:
{
  flake.tests.deadbugs-issue-254.hm-user-includes = {

    test-hm-user = denTest (
      {
        den,
        lib,
        igloo, # igloo = nixosConfigurations.igloo.config
        tuxHm, # tuxHm = igloo.home-manager.users.tux
        ...
      }:
      {
        den.default.homeManager.home.stateVersion = "25.11";
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.user.includes = [
          {
            homeManager = {
              programs.nix-index.enable = true;
            };
          }
        ];

        den.aspects.tux.homeManager = {
          # Dont enable this, it should be set via den.schema.user.includes
          # programs.nix-index.enable = true;
        };

        expr = tuxHm.programs.nix-index.enable;
        expected = true;
      }
    );

    test-user = denTest (
      {
        den,
        lib,
        igloo, # igloo = nixosConfigurations.igloo.config
        tuxHm, # tuxHm = igloo.home-manager.users.tux
        ...
      }:
      {
        den.default.homeManager.home.stateVersion = "25.11";
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.user.includes = [
          {
            homeManager = {
              programs.nix-index.enable = true;
            };
          }
        ];

        expr = tuxHm.programs.nix-index.enable;
        expected = true;
      }
    );

    test-hm-host = denTest (
      {
        den,
        lib,
        igloo, # igloo = nixosConfigurations.igloo.config
        tuxHm, # tuxHm = igloo.home-manager.users.tux
        ...
      }:
      {
        den.default.homeManager.home.stateVersion = "25.11";
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.host.includes = [
          {
            nixos = {
              home-manager.useGlobalPkgs = true;
            };
          }
        ];

        expr = igloo.home-manager.useGlobalPkgs;
        expected = true;
      }
    );

    # ensure the same issue occurs for other home-like classes (hjem)
    test-hjem-user = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "hjem" ];

        # hijack a minimal module so hostConf doesn't complain about missing
        # inputs.hjem. A plain empty attrset is enough for our test.
        den.hosts.x86_64-linux.igloo.hjem.module = {
          options.hjem.users = lib.mkOption {
            type = lib.types.lazyAttrsOf (
              lib.types.submodule {
                options.foo = lib.mkOption {
                  type = lib.types.str;
                  default = "<notset>";
                };
              }
            );
          };
        };

        den.schema.user.includes = [
          {
            hjem.foo = "bar";
          }
        ];

        expr = igloo.hjem.users.tux.foo;
        expected = "bar";
      }
    );

  };
}
