{ denTest, ... }:
{

  flake.tests.deadbugs-static-include-dups = {

    test-static-include = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.default.homeManager.home.stateVersion = "25.11";

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.includes = [
          {
            homeManager =
              { pkgs, ... }:
              {
                programs.emacs.enable = true;
                programs.emacs.package = pkgs.emacs-nox;
              };
          }
        ];

        expr = lib.getName tuxHm.programs.emacs.package;
        expected = "emacs-nox";
      }
    );

    test-default-func-include = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.default.homeManager.home.stateVersion = "25.11";

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.nixos.imports = [
          { options.foo = lib.mkOption { type = lib.types.listOf lib.types.str; }; }
        ];

        den.default.includes = [
          (
            { user, ... }:
            {
              nixos.foo = [ user.name ];
            }
          )
        ];

        expr = igloo.foo;
        expected = [ "tux" ];
      }
    );

    test-host-owned = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.default.homeManager.home.stateVersion = "25.11";

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          {
            nixos.imports = [
              { options.foo = lib.mkOption { type = lib.types.listOf lib.types.str; }; }
            ];
          }
        ];

        den.aspects.igloo.nixos.foo = [ "bar" ];

        expr = igloo.foo;
        expected = [ "bar" ];
      }
    );

    test-default-owned-package = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.nixos =
          { pkgs, ... }:
          {
            services.locate.package = pkgs.plocate;
          };

        expr = lib.getName igloo.services.locate.package;
        expected = "plocate";
      }
    );

    test-default-static-package = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.includes = [
          {
            name = "plocate-locate";
            nixos =
              { pkgs, ... }:
              {
                services.locate.package = pkgs.plocate;
              };
          }
        ];

        expr = lib.getName igloo.services.locate.package;
        expected = "plocate";
      }
    );

    test-default-owned-list = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.nixos.imports = [
          {
            options.tags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
          }
        ];
        den.default.nixos.tags = [ "server" ];

        expr = igloo.tags;
        expected = [ "server" ];
      }
    );

    test-host-owned-package = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.nixos =
          { pkgs, ... }:
          {
            services.locate.package = pkgs.plocate;
          };

        expr = lib.getName igloo.services.locate.package;
        expected = "plocate";
      }
    );

    test-host-owned-list = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.nixos.imports = [
          {
            options.tags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
          }
        ];
        den.aspects.igloo.nixos.tags = [ "server" ];

        expr = igloo.tags;
        expected = [ "server" ];
      }
    );

    test-default-list-multi-user = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.default.nixos.imports = [
          {
            options.tags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
          }
        ];
        den.default.nixos.tags = [ "server" ];

        expr = igloo.tags;
        expected = [ "server" ];
      }
    );

  };

}
