{ denTest, ... }:
{
  flake.tests.user-host-mutual-config = {

    test-host-owned-unidirectional = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        # no mutuality enabled, this is ignored
        den.aspects.igloo.homeManager.programs.direnv.enable = true;

        expr = [
          tuxHm.programs.direnv.enable
          pinguHm.programs.direnv.enable
        ];
        expected = [
          false
          false
        ];
      }
    );

    test-host-owned-mutual = denTest (
      {
        den,
        lib,
        tuxHm,
        pinguHm,
        ...
      }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.policies.to-users =
          { host, user, ... }:
          [
            (include {
              homeManager.programs.direnv.enable = true;
            })
          ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.to-users ];

        expr = [
          tuxHm.programs.direnv.enable
          pinguHm.programs.direnv.enable
        ];
        expected = [
          true
          true
        ];
      }
    );

    test-host-mutual-static-includes-configures-all-users = denTest (
      {
        den,
        lib,
        tuxHm,
        pinguHm,
        ...
      }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.policies.to-users =
          { host, user, ... }:
          [
            (include {
              includes = [
                {
                  homeManager.programs.direnv.enable = true;
                }
              ];
            })
          ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.to-users ];

        expr = [
          tuxHm.programs.direnv.enable
          pinguHm.programs.direnv.enable
        ];
        expected = [
          true
          true
        ];
      }
    );

    test-host-parametric-unidirectional = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        ...
      }:
      {

        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.includes = [
          (
            { host, user }:
            {
              homeManager.programs.direnv.enable = true;
            }
          )
        ];

        expr = [
          tuxHm.programs.direnv.enable
          pinguHm.programs.direnv.enable
        ];
        # { host, user } parametric includes resolve once per user
        # when both args are available (fan-out via deferred drain).
        expected = [
          true
          true
        ];
      }
    );

    test-host-parametric-mutual = denTest (
      {
        den,
        lib,
        tuxHm,
        pinguHm,
        ...
      }:
      let
        inherit (den.lib.policy) include;
      in
      {

        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.policies.to-users =
          { host, user, ... }:
          [
            (include {
              includes = [
                (
                  { host, user }:
                  {
                    homeManager.programs.direnv.enable = true;
                  }
                )
              ];
            })
          ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.to-users ];

        expr = [
          tuxHm.programs.direnv.enable
          pinguHm.programs.direnv.enable
        ];
        expected = [
          true
          true
        ];
      }
    );

    test-user-owned-configures-all-hosts = denTest (
      {
        den,
        igloo,
        iceberg,
        ...
      }:
      {

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };

        den.aspects.tux.nixos.programs.fish.enable = true;

        expr = [
          igloo.programs.fish.enable
          iceberg.programs.fish.enable
        ];
        expected = [
          true
          true
        ];
      }
    );

    test-user-static-unidirectional-configures-all-hosts = denTest (
      {
        den,
        igloo,
        iceberg,
        ...
      }:
      {

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };

        den.aspects.tux.includes = [
          {
            nixos.programs.fish.enable = true;
          }
        ];

        expr = [
          igloo.programs.fish.enable
          iceberg.programs.fish.enable
        ];
        expected = [
          true
          true
        ];
      }
    );

    test-user-function-configures-all-hosts = denTest (
      {
        den,
        igloo,
        iceberg,
        ...
      }:
      {

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };

        den.aspects.tux.includes = [
          (
            { host, user }:
            {
              nixos.programs.fish.enable = true;
            }
          )
        ];

        expr = [
          igloo.programs.fish.enable
          iceberg.programs.fish.enable
        ];
        expected = [
          true
          true
        ];
      }
    );

    # Host-level selective provide-to-users (the legacy mutual-provider pattern).
    # Registered at the HOST (`den.aspects.igloo`), whose subtree spans every
    # user, so it legitimately fans to all of them — and may select per user.
    # (Was `test-user-provides-to-all-users`, registered at `den.aspects.tux`;
    # a user reaching siblings is no longer allowed — see
    # `test-user-include-stays-in-subtree` below.)
    test-host-provides-selectively-to-users = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          alice = { };
          bob = { };
          carl = { };
        };

        den.aspects.igloo.policies.to-users =
          { host, user, ... }:
          lib.optional (user.name != "tux") (include {
            homeManager.programs.vim.enable = true;
          });

        den.aspects.igloo.policies.to-alice =
          { host, user, ... }:
          lib.optional (user.name == "alice") (include {
            homeManager.programs.tmux.enable = true;
          });
        den.aspects.igloo.includes = [
          den.aspects.igloo.policies.to-users
          den.aspects.igloo.policies.to-alice
        ];

        expr = with igloo.home-manager.users; {
          tux = tux.programs.vim.enable;
          alice = alice.programs.vim.enable;
          bob = bob.programs.vim.enable;
          carl = carl.programs.vim.enable;
          aliceTmux = alice.programs.tmux.enable;
          bobTmux = bob.programs.tmux.enable;
        };

        expected = {
          tux = false;
          alice = true;
          bob = true;
          carl = true;
          aliceTmux = true;
          bobTmux = false;
        };

      }
    );

    # A policy registered via a USER's own includes is subtree-scoped: it
    # applies to that user, never to sibling users. (To configure all users,
    # register at the host — see `test-host-provides-selectively-to-users`.)
    test-user-include-stays-in-subtree = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        ...
      }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.tux.policies.to-users =
          { host, user, ... }: [ (include { homeManager.programs.vim.enable = true; }) ];
        den.aspects.tux.includes = [ den.aspects.tux.policies.to-users ];

        expr = [
          tuxHm.programs.vim.enable
          pinguHm.programs.vim.enable
        ];
        # tux's own include reaches tux only; pingu (a sibling) is untouched.
        expected = [
          true
          false
        ];
      }
    );

  };
}
