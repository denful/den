{ denTest, lib, ... }:
{
  flake.tests.parametric-fixedTo =
    let
      test-option = {
        nixos.options.test = lib.mkOption { type = lib.types.listOf lib.types.str; };
      };

      owned = aspect-name: {
        nixos.test = [ "${aspect-name}-owned" ];
      };

      parametric-include =
        aspect-name:
        { host, ... }:
        {
          includes = [
            {
              nixos.test = [ "${aspect-name}-parametric-include-${host.name}" ];
            }
          ];
        };

      nested-parametric = aspect-name: {
        includes = [
          (
            { host, ... }:
            {
              nixos.test = [ "${aspect-name}-nested-parametric-${host.name}" ];
            }
          )
        ];
      };

      static =
        aspect-name:
        { class, ... }:
        {
          nixos.test = [ "${aspect-name}-static-${class}" ];
        };

      parametric-exactly-host =
        aspect-name:
        { host }:
        {
          nixos.test = [ "${aspect-name}-parametric-exactly-host-${host.name}" ];
        };

      parametric-exactly-user =
        aspect-name:
        { user }:
        {
          nixos.test = [ "${aspect-name}-parametric-exactly-user-${user.userName}" ];
        };

      parametric-atLeast-host =
        aspect-name:
        { host, ... }:
        {
          nixos.test = [ "${aspect-name}-parametric-atLeast-host-${host.name}" ];
        };

      parametric-exactly-host-user =
        aspect-name:
        { host, user }:
        {
          nixos.test = [ "${aspect-name}-parametric-exactly-host-user-${host.name}-${user.userName}" ];
        };

      parametric-atLeast-user =
        aspect-name:
        { user, ... }:
        {
          nixos.test = [ "${aspect-name}-parametric-atLeast-user-${user.userName}" ];
        };

      named-aspect = aspect-name: includes: {
        includes = map (include: include aspect-name) includes;
      };

      test-aspect =
        includes:
        let
          inner = _: named-aspect "inner" includes;
        in
        named-aspect "outer" (includes ++ lib.singleton inner);
    in
    {
      test-base-parametric-host-context =
        let
          aspects = [
            owned
            static
            parametric-include
            parametric-exactly-host
            parametric-exactly-user
            parametric-exactly-host-user
            parametric-atLeast-host
            parametric-atLeast-user
          ];
        in
        denTest (
          { igloo, ... }:
          {
            den.hosts.x86_64-linux.igloo.users.tux = { };
            den.hosts.x86_64-linux.igloo.users.gnu = { };

            den.schema.host.includes = [
              test-option
              (test-aspect aspects)
            ];

            expr = lib.sort lib.lessThan igloo.test;
            # Fan-out: { user } and { host, user } parametric includes
            # drain once per user scope (tux + gnu).
            expected = [
              "inner-owned"
              "inner-parametric-atLeast-host-igloo"
              "inner-parametric-atLeast-user-gnu"
              "inner-parametric-atLeast-user-tux"
              "inner-parametric-exactly-host-igloo"
              "inner-parametric-exactly-host-user-igloo-gnu"
              "inner-parametric-exactly-host-user-igloo-tux"
              "inner-parametric-exactly-user-gnu"
              "inner-parametric-exactly-user-tux"
              "inner-parametric-include-igloo"
              "inner-static-nixos"
              "outer-owned"
              "outer-parametric-atLeast-host-igloo"
              "outer-parametric-atLeast-user-gnu"
              "outer-parametric-atLeast-user-tux"
              "outer-parametric-exactly-host-igloo"
              "outer-parametric-exactly-host-user-igloo-gnu"
              "outer-parametric-exactly-host-user-igloo-tux"
              "outer-parametric-exactly-user-gnu"
              "outer-parametric-exactly-user-tux"
              "outer-parametric-include-igloo"
              "outer-static-nixos"
            ];
          }
        );

      test-base-parametric-user-context =
        let
          aspects = [
            owned
            static
            parametric-include
            # This causes an error with the base parametric type as they're called with extra types
            # parametric-exactly-host
            # parametric-exactly-user
            parametric-exactly-host-user
            parametric-atLeast-host
            parametric-atLeast-user
          ];
        in
        denTest (
          { igloo, ... }:
          {
            den.hosts.x86_64-linux.igloo.users.tux = { };
            den.hosts.x86_64-linux.igloo.users.gnu = { };

            den.schema.host.includes = [
              test-option
            ];

            den.schema.user.includes = [
              (test-aspect aspects)
            ];

            expr = lib.sort lib.lessThan igloo.test;

            # We expect double inclusion of atLeast-host, owned, and static because they are included by both user contexts
            expected = [
              "inner-owned"
              "inner-owned"
              "inner-parametric-atLeast-host-igloo"
              "inner-parametric-atLeast-host-igloo"
              "inner-parametric-atLeast-user-gnu"
              "inner-parametric-atLeast-user-tux"
              "inner-parametric-exactly-host-user-igloo-gnu"
              "inner-parametric-exactly-host-user-igloo-tux"
              "inner-parametric-include-igloo"
              "inner-parametric-include-igloo"
              "inner-static-homeManager"
              "inner-static-homeManager"
              "outer-owned"
              "outer-owned"
              "outer-parametric-atLeast-host-igloo"
              "outer-parametric-atLeast-host-igloo"
              "outer-parametric-atLeast-user-gnu"
              "outer-parametric-atLeast-user-tux"
              "outer-parametric-exactly-host-user-igloo-gnu"
              "outer-parametric-exactly-host-user-igloo-tux"
              "outer-parametric-include-igloo"
              "outer-parametric-include-igloo"
              "outer-static-homeManager"
              "outer-static-homeManager"
            ];
          }
        );

      test-base-parametric-fixedTo-exactly-host-context =
        let
          aspects = [
            owned
            static
            parametric-include
            nested-parametric
            parametric-exactly-host
            parametric-exactly-user
            parametric-exactly-host-user
            parametric-atLeast-host
            parametric-atLeast-user
          ];
        in
        denTest (
          { den, igloo, ... }:
          {
            den.hosts.x86_64-linux.igloo.users.tux = { };
            den.hosts.x86_64-linux.igloo.users.gnu = { };

            den.schema.host.includes = [
              test-option
              ({ host }: den.lib.parametric.fixedTo.exactly { inherit host; } (test-aspect aspects))
            ];

            expr = lib.sort lib.lessThan igloo.test;
            expected = [
              "inner-nested-parametric-igloo"
              "inner-owned"
              "inner-parametric-atLeast-host-igloo"
              "inner-parametric-atLeast-user-gnu"
              "inner-parametric-atLeast-user-tux"
              "inner-parametric-exactly-host-igloo"
              "inner-parametric-exactly-host-user-igloo-gnu"
              "inner-parametric-exactly-host-user-igloo-tux"
              "inner-parametric-exactly-user-gnu"
              "inner-parametric-exactly-user-tux"
              "inner-parametric-include-igloo"
              "inner-static-nixos"
              "outer-nested-parametric-igloo"
              "outer-owned"
              "outer-parametric-atLeast-host-igloo"
              "outer-parametric-atLeast-user-gnu"
              "outer-parametric-atLeast-user-tux"
              "outer-parametric-exactly-host-igloo"
              "outer-parametric-exactly-host-user-igloo-gnu"
              "outer-parametric-exactly-host-user-igloo-tux"
              "outer-parametric-exactly-user-gnu"
              "outer-parametric-exactly-user-tux"
              "outer-parametric-include-igloo"
              "outer-static-nixos"
            ];
          }
        );

      test-base-parametric-fixedTo-exactly-user-context =
        let
          aspects = [
            owned
            static
            parametric-include
            nested-parametric
            parametric-exactly-host
            parametric-exactly-user
            parametric-exactly-host-user
            parametric-atLeast-host
            parametric-atLeast-user
          ];
        in
        denTest (
          { den, igloo, ... }:
          {
            den.hosts.x86_64-linux.igloo.users.tux = { };
            den.hosts.x86_64-linux.igloo.users.gnu = { };

            den.schema.host.includes = [
              test-option
            ];

            den.schema.user.includes = [
              ({ host, user }: den.lib.parametric.fixedTo.exactly { inherit host user; } (test-aspect aspects))
            ];

            expr = lib.sort lib.lessThan igloo.test;
            expected = [
              "inner-nested-parametric-igloo"
              "inner-nested-parametric-igloo"
              "inner-owned"
              "inner-owned"
              "inner-parametric-atLeast-host-igloo"
              "inner-parametric-atLeast-host-igloo"
              "inner-parametric-atLeast-user-gnu"
              "inner-parametric-atLeast-user-tux"
              "inner-parametric-exactly-host-igloo"
              "inner-parametric-exactly-host-igloo"
              "inner-parametric-exactly-host-user-igloo-gnu"
              "inner-parametric-exactly-host-user-igloo-tux"
              "inner-parametric-exactly-user-gnu"
              "inner-parametric-exactly-user-tux"
              "inner-parametric-include-igloo"
              "inner-parametric-include-igloo"
              "inner-static-homeManager"
              "inner-static-homeManager"
              "outer-nested-parametric-igloo"
              "outer-nested-parametric-igloo"
              "outer-owned"
              "outer-owned"
              "outer-parametric-atLeast-host-igloo"
              "outer-parametric-atLeast-host-igloo"
              "outer-parametric-atLeast-user-gnu"
              "outer-parametric-atLeast-user-tux"
              "outer-parametric-exactly-host-igloo"
              "outer-parametric-exactly-host-igloo"
              "outer-parametric-exactly-host-user-igloo-gnu"
              "outer-parametric-exactly-host-user-igloo-tux"
              "outer-parametric-exactly-user-gnu"
              "outer-parametric-exactly-user-tux"
              "outer-parametric-include-igloo"
              "outer-parametric-include-igloo"
              "outer-static-homeManager"
              "outer-static-homeManager"
            ];
          }
        );

      test-base-parametric-fixedTo-atLeast-host-context =
        let
          aspects = [
            owned
            static
            parametric-include
            nested-parametric
            parametric-exactly-host
            parametric-exactly-user
            parametric-exactly-host-user
            parametric-atLeast-host
            parametric-atLeast-user
          ];
        in
        denTest (
          { den, igloo, ... }:
          {
            den.hosts.x86_64-linux.igloo.users.tux = { };
            den.hosts.x86_64-linux.igloo.users.gnu = { };

            den.schema.host.includes = [
              test-option
              ({ host }: den.lib.parametric.fixedTo.atLeast { inherit host; } (test-aspect aspects))
            ];

            den.schema.user.includes = [ ];

            expr = lib.sort lib.lessThan igloo.test;
            expected = [
              "inner-nested-parametric-igloo"
              "inner-owned"
              "inner-parametric-atLeast-host-igloo"
              "inner-parametric-atLeast-user-gnu"
              "inner-parametric-atLeast-user-tux"
              "inner-parametric-exactly-host-igloo"
              "inner-parametric-exactly-host-user-igloo-gnu"
              "inner-parametric-exactly-host-user-igloo-tux"
              "inner-parametric-exactly-user-gnu"
              "inner-parametric-exactly-user-tux"
              "inner-parametric-include-igloo"
              "inner-static-nixos"
              "outer-nested-parametric-igloo"
              "outer-owned"
              "outer-parametric-atLeast-host-igloo"
              "outer-parametric-atLeast-user-gnu"
              "outer-parametric-atLeast-user-tux"
              "outer-parametric-exactly-host-igloo"
              "outer-parametric-exactly-host-user-igloo-gnu"
              "outer-parametric-exactly-host-user-igloo-tux"
              "outer-parametric-exactly-user-gnu"
              "outer-parametric-exactly-user-tux"
              "outer-parametric-include-igloo"
              "outer-static-nixos"
            ];
          }
        );

      test-base-parametric-fixedTo-atLeast-user-context =
        let
          aspects = [
            owned
            static
            parametric-include
            nested-parametric
            # parametric-exactly-host
            # parametric-exactly-user
            parametric-exactly-host-user
            parametric-atLeast-host
            parametric-atLeast-user
          ];
        in
        denTest (
          { den, igloo, ... }:
          {
            den.hosts.x86_64-linux.igloo.users.tux = { };
            den.hosts.x86_64-linux.igloo.users.gnu = { };

            den.schema.host.includes = [
              test-option
            ];

            den.schema.user.includes = [
              ({ host, user }: den.lib.parametric.fixedTo.atLeast { inherit host user; } (test-aspect aspects))
            ];

            expr = lib.sort lib.lessThan igloo.test;
            expected = [
              "inner-nested-parametric-igloo"
              "inner-nested-parametric-igloo"
              "inner-owned"
              "inner-owned"
              "inner-parametric-atLeast-host-igloo"
              "inner-parametric-atLeast-host-igloo"
              "inner-parametric-atLeast-user-gnu"
              "inner-parametric-atLeast-user-tux"
              "inner-parametric-exactly-host-user-igloo-gnu"
              "inner-parametric-exactly-host-user-igloo-tux"
              "inner-parametric-include-igloo"
              "inner-parametric-include-igloo"
              "inner-static-homeManager"
              "inner-static-homeManager"
              "outer-nested-parametric-igloo"
              "outer-nested-parametric-igloo"
              "outer-owned"
              "outer-owned"
              "outer-parametric-atLeast-host-igloo"
              "outer-parametric-atLeast-host-igloo"
              "outer-parametric-atLeast-user-gnu"
              "outer-parametric-atLeast-user-tux"
              "outer-parametric-exactly-host-user-igloo-gnu"
              "outer-parametric-exactly-host-user-igloo-tux"
              "outer-parametric-include-igloo"
              "outer-parametric-include-igloo"
              "outer-static-homeManager"
              "outer-static-homeManager"
            ];
          }
        );

      test-base-parametric-fixedTo-upTo-host-context =
        let
          aspects = [
            owned
            static
            parametric-include
            nested-parametric
            parametric-exactly-host
            parametric-exactly-user
            parametric-exactly-host-user
            parametric-atLeast-host
            parametric-atLeast-user
          ];
        in
        denTest (
          { den, igloo, ... }:
          {
            den.hosts.x86_64-linux.igloo.users.tux = { };
            den.hosts.x86_64-linux.igloo.users.gnu = { };

            den.schema.host.includes = [
              test-option
              ({ host }: den.lib.parametric.fixedTo.upTo { inherit host; } (test-aspect aspects))
            ];

            expr = lib.sort lib.lessThan igloo.test;
            expected = [
              "inner-nested-parametric-igloo"
              "inner-owned"
              "inner-parametric-atLeast-host-igloo"
              "inner-parametric-atLeast-user-gnu"
              "inner-parametric-atLeast-user-tux"
              "inner-parametric-exactly-host-igloo"
              "inner-parametric-exactly-host-user-igloo-gnu"
              "inner-parametric-exactly-host-user-igloo-tux"
              "inner-parametric-exactly-user-gnu"
              "inner-parametric-exactly-user-tux"
              "inner-parametric-include-igloo"
              "inner-static-nixos"
              "outer-nested-parametric-igloo"
              "outer-owned"
              "outer-parametric-atLeast-host-igloo"
              "outer-parametric-atLeast-user-gnu"
              "outer-parametric-atLeast-user-tux"
              "outer-parametric-exactly-host-igloo"
              "outer-parametric-exactly-host-user-igloo-gnu"
              "outer-parametric-exactly-host-user-igloo-tux"
              "outer-parametric-exactly-user-gnu"
              "outer-parametric-exactly-user-tux"
              "outer-parametric-include-igloo"
              "outer-static-nixos"
            ];
          }
        );

      test-base-parametric-fixedTo-upTo-user-context =
        let
          aspects = [
            owned
            static
            parametric-include
            nested-parametric
            parametric-exactly-host
            parametric-exactly-user
            parametric-exactly-host-user
            parametric-atLeast-host
            parametric-atLeast-user
          ];
        in
        denTest (
          { den, igloo, ... }:
          {
            den.hosts.x86_64-linux.igloo.users.tux = { };
            den.hosts.x86_64-linux.igloo.users.gnu = { };

            den.schema.host.includes = [
              test-option
            ];

            den.schema.user.includes = [
              ({ host, user }: den.lib.parametric.fixedTo.upTo { inherit host user; } (test-aspect aspects))
            ];

            expr = lib.sort lib.lessThan igloo.test;
            expected = [
              "inner-nested-parametric-igloo"
              "inner-nested-parametric-igloo"
              "inner-owned"
              "inner-owned"
              "inner-parametric-atLeast-host-igloo"
              "inner-parametric-atLeast-host-igloo"
              "inner-parametric-atLeast-user-gnu"
              "inner-parametric-atLeast-user-tux"
              "inner-parametric-exactly-host-igloo"
              "inner-parametric-exactly-host-igloo"
              "inner-parametric-exactly-host-user-igloo-gnu"
              "inner-parametric-exactly-host-user-igloo-tux"
              "inner-parametric-exactly-user-gnu"
              "inner-parametric-exactly-user-tux"
              "inner-parametric-include-igloo"
              "inner-parametric-include-igloo"
              "inner-static-homeManager"
              "inner-static-homeManager"
              "outer-nested-parametric-igloo"
              "outer-nested-parametric-igloo"
              "outer-owned"
              "outer-owned"
              "outer-parametric-atLeast-host-igloo"
              "outer-parametric-atLeast-host-igloo"
              "outer-parametric-atLeast-user-gnu"
              "outer-parametric-atLeast-user-tux"
              "outer-parametric-exactly-host-igloo"
              "outer-parametric-exactly-host-igloo"
              "outer-parametric-exactly-host-user-igloo-gnu"
              "outer-parametric-exactly-host-user-igloo-tux"
              "outer-parametric-exactly-user-gnu"
              "outer-parametric-exactly-user-tux"
              "outer-parametric-include-igloo"
              "outer-parametric-include-igloo"
              "outer-static-homeManager"
              "outer-static-homeManager"
            ];
          }
        );

    };
}
