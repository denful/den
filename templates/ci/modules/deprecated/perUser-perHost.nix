{ denTest, ... }:
{
  flake.tests.perUser-perHost = {

    test-included-in-default-pipeline = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.nixos.options.funny = lib.mkOption {
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };

        # Post-ctx: drain-deferred resolves deferred includes when context
        # widens. perUser/perHost guards (deprecated) can't distinguish
        # "host aspect drained with user context" from "user aspect
        # directly resolved." Both see {host, user} without home.
        # Test updated to reflect post-ctx drain semantics.
        den.aspects.igloo.includes = [
          (den.lib.perHost { nixos.funny = [ "atHost perHost static" ]; })
          (den.lib.perHost (
            { host }:
            {
              nixos.funny = [ "atHost perHost ${host.name} fun" ];
            }
          ))
          (den.lib.perUser { nixos.funny = [ "atHost perUser static" ]; })
          (den.lib.perUser (
            { user, host }:
            {
              nixos.funny = [ "atHost perUser ${user.name}@${host.name} fun" ];
            }
          ))
        ];

        den.aspects.tux.includes = [
          (den.lib.perHost { nixos.funny = [ "atUser perHost static" ]; })
          (den.lib.perHost (
            { host }:
            {
              nixos.funny = [ "atUser perHost ${host.name} fun" ];
            }
          ))
          (den.lib.perUser { nixos.funny = [ "atUser perUser static" ]; })
          (den.lib.perUser (
            { user, host }:
            {
              nixos.funny = [ "atUser perUser ${user.name}@${host.name} fun" ];
            }
          ))
        ];

        expr = lib.sort lib.lessThan igloo.funny;
        # Fan-out: perUser includes on host aspect drain once per user
        # scope. Static variants produce identical output at each scope
        # (appearing twice in the merged list). Fun variants produce
        # per-user distinct output.
        expected = [
          "atHost perHost igloo fun"
          "atHost perHost static"
          "atHost perUser pingu@igloo fun"
          "atHost perUser static"
          "atHost perUser static"
          "atHost perUser tux@igloo fun"
          "atUser perUser static"
          "atUser perUser tux@igloo fun"
        ];
      }
    );

    test-included-in-mutual-pipeline = denTest (
      {
        den,
        igloo,
        lib,
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

        den.aspects.igloo.nixos.options.funny = lib.mkOption {
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };

        den.aspects.igloo.policies.to-users =
          { host, user, ... }:
          [
            (include {
              includes = [
                (den.lib.perHost { nixos.funny = [ (throw "atHost perHost static") ]; })
                (den.lib.perHost (
                  { host }:
                  {
                    nixos.funny = [ (throw "atHost perHost ${host.name} fun") ];
                  }
                ))
                (den.lib.perUser { nixos.funny = [ "atHost perUser static" ]; })
                (den.lib.perUser (
                  { user, host }:
                  {
                    nixos.funny = [ "atHost perUser ${user.name}@${host.name} fun" ];
                  }
                ))
              ];
            })
          ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.to-users ];

        den.aspects.tux.includes = [
          (den.lib.perHost { nixos.funny = [ "atUser ignored perHost static" ]; })
          (den.lib.perHost (
            { host }:
            {
              nixos.funny = [ "atUser ignored perHost ${host.name} fun" ];
            }
          ))
          (den.lib.perUser { nixos.funny = [ "atUser perUser static" ]; })
          (den.lib.perUser (
            { user, host }:
            {
              nixos.funny = [ "atUser perUser ${user.name}@${host.name} fun" ];
            }
          ))
        ];

        expr = lib.sort lib.lessThan igloo.funny;
        expected = [
          "atHost perUser pingu@igloo fun"
          "atHost perUser static"
          "atHost perUser static"
          "atHost perUser tux@igloo fun"
          "atUser perUser static"
          "atUser perUser tux@igloo fun"
        ];
      }
    );

    test-perHome-on-standalone-home = denTest (
      {
        den,
        config,
        lib,
        ...
      }:
      {
        den.homes.x86_64-linux.tux = { };
        den.default.includes = [ den.provides.define-user ];

        den.aspects.tux.homeManager.options.funny = lib.mkOption {
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };

        den.aspects.tux.includes = [
          (den.lib.perHost { homeManager.funny = [ "atHome IGNORED perHost static" ]; })
          (den.lib.perHost (
            { host }:
            {
              homeManager.funny = [ "atHome IGNORED perHost ${host.name} fun" ];
            }
          ))
          (den.lib.perUser { homeManager.funny = [ "atHome IGNORED perUser static" ]; })
          (den.lib.perUser (
            { user, host }:
            {
              homeManager.funny = [ "atHome IGNORED perUser ${user.name}@${host.name} fun" ];
            }
          ))
          (den.lib.perHome { homeManager.funny = [ "atHome perHome static" ]; })
          (den.lib.perHome (
            { home }:
            {
              homeManager.funny = [ "atHome perHome ${home.name} fun" ];
            }
          ))
        ];

        expr = lib.sort lib.lessThan config.flake.homeConfigurations.tux.config.funny;
        expected = [
          "atHome perHome static"
          "atHome perHome tux fun"
        ];
      }
    );

  };
}
