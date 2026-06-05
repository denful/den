# Battery: host-aspects — projects host homeManager configs to opted-in users.
{ denTest, ... }:
{
  flake.tests.host-aspects = {

    # Host aspect with homeManager key projects to user who includes den._.host-aspects.
    test-host-hm-projects-to-user = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.homeManager.programs.vim.enable = true;
        den.aspects.tux.includes = [ den._.host-aspects ];

        expr = tuxHm.programs.vim.enable;
        expected = true;
      }
    );

    # Host aspect with only nixos key does NOT leak into user's homeManager.
    test-nixos-only-does-not-leak = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.nixos.networking.hostName = "igloo";
        den.aspects.tux.includes = [ den._.host-aspects ];

        expr = tuxHm.programs.vim.enable;
        expected = false;
      }
    );

    # Verify no circular eval when accessing both host and user configs.
    test-no-circular-eval = denTest (
      {
        den,
        lib,
        igloo,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.homeManager.programs.vim.enable = true;
        den.aspects.igloo.nixos.networking.hostName = "igloo";
        den.aspects.tux.includes = [ den._.host-aspects ];

        expr = {
          hostName = igloo.networking.hostName;
          vim = tuxHm.programs.vim.enable;
        };
        expected = {
          hostName = "igloo";
          vim = true;
        };
      }
    );

    # Multiple host sub-aspects with homeManager keys all project.
    test-multiple-host-aspects = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          { homeManager.programs.vim.enable = true; }
          { homeManager.programs.git.enable = true; }
        ];

        den.aspects.tux.includes = [ den._.host-aspects ];

        expr = {
          vim = tuxHm.programs.vim.enable;
          git = tuxHm.programs.git.enable;
        };
        expected = {
          vim = true;
          git = true;
        };
      }
    );

    # Host nixos modules are NOT duplicated when user includes host-aspects.
    # Uses a listOf option to detect double-application.
    test-no-nixos-duplication = denTest (
      {
        den,
        lib,
        igloo,
        tuxHm,
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

        den.aspects.igloo = {
          nixos.tags = [ "host" ];
          homeManager.programs.vim.enable = true;
        };

        den.aspects.tux.includes = [ den._.host-aspects ];

        expr = {
          tags = igloo.tags;
          vim = tuxHm.programs.vim.enable;
        };
        expected = {
          # "host" should appear exactly once — not duplicated
          tags = [ "host" ];
          vim = true;
        };
      }
    );

    # Host sub-aspects with homeManager project through includes.
    # Shared aspects (included by both host and user) must not cause
    # duplicate module conflicts.
    test-shared-sub-aspects-no-duplication = denTest (
      {
        den,
        lib,
        igloo,
        tuxHm,
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
        den.default.homeManager.imports = [
          {
            options.hm-tags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
          }
        ];

        # Shared aspect: included by BOTH host and user directly.
        den.aspects.shared-tools = {
          nixos.tags = [ "shared" ];
          homeManager.hm-tags = [ "shared" ];
        };

        # Host-only aspect with homeManager config.
        den.aspects.host-desktop = {
          nixos.tags = [ "desktop" ];
          homeManager.hm-tags = [ "desktop" ];
        };

        den.aspects.igloo = {
          nixos.tags = [ "host" ];
          includes = [
            den.aspects.shared-tools
            den.aspects.host-desktop
          ];
        };

        den.aspects.tux = {
          includes = [
            den.aspects.shared-tools # also included by host
            den._.host-aspects
          ];
          homeManager.hm-tags = [ "user" ];
        };

        expr = {
          # nixos tags: host + shared + desktop (each exactly once)
          nixosTags = lib.sort (a: b: a < b) igloo.tags;
          # shared appears via both direct user include AND host-aspects — must not conflict
          # hm tags: user's own + shared (direct) + desktop (via host-aspects) + shared (via host-aspects)
          # shared appears via both direct include and host-aspects — must not conflict
          hmHasDesktop = builtins.elem "desktop" tuxHm.hm-tags;
          hmHasUser = builtins.elem "user" tuxHm.hm-tags;
          hmHasShared = builtins.elem "shared" tuxHm.hm-tags;
        };
        expected = {
          nixosTags = [
            "desktop"
            "host"
            "shared"
          ];
          hmHasDesktop = true;
          hmHasUser = true;
          hmHasShared = true;
        };
      }
    );

    # Overlap: user includes an aspect directly AND it appears in host tree
    # via host-aspects. Module dedup prevents duplicate option declarations.
    test-overlap-no-conflict = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.homeManager.imports = [
          {
            options.hm-tags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
          }
        ];

        den.aspects.shared-tool = {
          homeManager.hm-tags = [ "shared" ];
        };

        den.aspects.igloo.includes = [ den.aspects.shared-tool ];

        # User includes shared-tool directly AND via host-aspects (overlap).
        den.aspects.tux.includes = [
          den.aspects.shared-tool
          den._.host-aspects
        ];

        expr = tuxHm.hm-tags;
        expected = [ "shared" ];
      }
    );

    # Multiple users each get distinct homeManager modules from a named
    # host sub-aspect that uses the user arg. The key dedup must not
    # collapse modules across users — each user's resolve call has its
    # own key namespace.
    test-multi-user-distinct = denTest (
      {
        den,
        lib,
        tuxHm,
        pinguHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.user-greeting =
          { user, ... }:
          {
            homeManager.home.sessionVariables.GREETING = "hello-${user.name}";
          };

        den.aspects.igloo.includes = [ den.aspects.user-greeting ];

        den.aspects.tux.includes = [ den._.host-aspects ];
        den.aspects.pingu.includes = [ den._.host-aspects ];

        expr = {
          tux = tuxHm.home.sessionVariables.GREETING;
          pingu = pinguHm.home.sessionVariables.GREETING;
        };
        expected = {
          tux = "hello-tux";
          pingu = "hello-pingu";
        };
      }
    );

    # User who does NOT include den._.host-aspects does not receive host homeManager.
    test-opt-in-only = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.homeManager.programs.vim.enable = true;
        # tux does NOT include den._.host-aspects

        expr = tuxHm.programs.vim.enable;
        expected = false;
      }
    );

    # Host aspect with hjem key projects to user who includes den._.host-aspects.
    test-host-hjem-projects-to-user = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux.classes = [ "hjem" ];
          hjem.module.options.hjem.users = lib.mkOption {
            type = lib.types.lazyAttrsOf (
              lib.types.submodule {
                options.foo = lib.mkOption { };
              }
            );
          };

        };

        den.aspects.igloo.hjem.foo = true;
        den.aspects.tux.includes = [ den._.host-aspects ];

        expr = igloo.hjem.users.tux.foo;
        expected = true;
      }
    );

  };
}
