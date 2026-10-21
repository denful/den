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
          { nixos.funny = [ "atHost perHost static" ]; }
          (
            { host, ... }:
            {
              nixos.funny = [ "atHost perHost ${host.name} fun" ];
            }
          )
          { nixos.funny = [ "atHost perUser static" ]; }
          (
            { user, host, ... }:
            {
              nixos.funny = [ "atHost perUser ${user.name}@${host.name} fun" ];
            }
          )
        ];

        den.aspects.tux.includes = [
          { nixos.funny = [ "atUser perHost static" ]; }
          (
            { host, ... }:
            {
              nixos.funny = [ "atUser perHost ${host.name} fun" ];
            }
          )
          { nixos.funny = [ "atUser perUser static" ]; }
          (
            { user, host, ... }:
            {
              nixos.funny = [ "atUser perUser ${user.name}@${host.name} fun" ];
            }
          )
        ];

        expr = lib.sort lib.lessThan igloo.funny;
        # §6: host-aspect (igloo) includes resolve at host scope (ctx={host});
        # user-aspect (tux) includes resolve at user scope (ctx={host,user}).
        # { host } fn → in-ctx at its scope → binds once. { host, user } fn →
        # user is a descendant at host scope → fan-out per user; both in-ctx at
        # user scope → binds once. Bare static attrset → unconditional, emits
        # once at its scope (NO fan-out, no destructure to defer on).
        #
        # FLIPS vs perCtx shim:
        # - "atHost perUser static" x2 → x1: rule-correct. The old shim
        #   genuinely made the static parametric-on-user (intended ×2 fan-out);
        #   under the migration the per-user fan-out of identical static content
        #   RELOCATED to `relationship-fanout.test-identical-static-appears-per-user`.
        #   The bare static here has no destructure → emits ONCE at host scope.
        # - + "atUser perHost igloo fun", + "atUser perHost static": rule-correct.
        #   { host } / static on a USER aspect now BIND host from ctx at the user
        #   scope and emit there; the old perHost shim silently no-op'd (saw user
        #   extra). nixos content folds into the host config → NEW entries.
        expected = [
          "atHost perHost igloo fun"
          "atHost perHost static"
          "atHost perUser pingu@igloo fun"
          "atHost perUser static"
          "atHost perUser tux@igloo fun"
          "atUser perHost igloo fun"
          "atUser perHost static"
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
                { nixos.funny = [ "atHost perHost static" ]; }
                (
                  { host, ... }:
                  {
                    nixos.funny = [ "atHost perHost ${host.name} fun" ];
                  }
                )
                { nixos.funny = [ "atHost perUser static" ]; }
                (
                  { user, host, ... }:
                  {
                    nixos.funny = [ "atHost perUser ${user.name}@${host.name} fun" ];
                  }
                )
              ];
            })
          ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.to-users ];

        den.aspects.tux.includes = [
          { nixos.funny = [ "atUser perHost static" ]; }
          (
            { host, ... }:
            {
              nixos.funny = [ "atUser perHost ${host.name} fun" ];
            }
          )
          { nixos.funny = [ "atUser perUser static" ]; }
          (
            { user, host, ... }:
            {
              nixos.funny = [ "atUser perUser ${user.name}@${host.name} fun" ];
            }
          )
        ];

        expr = lib.sort lib.lessThan igloo.funny;
        # §6: the to-users policy on host-aspect igloo fans out per user
        # (ctx={host,user}); its include block runs once per user (tux, pingu).
        # Inside that ctx, { host } fn and bare statics BIND/emit (host in-ctx)
        # → x2 each (one per user). { host, user } fn → both in-ctx → per user.
        #
        # FLIPS vs perCtx shim:
        # - + "atHost perHost igloo fun" x2, + "atHost perHost static" x2:
        #   rule-correct. Inside to-users ctx={host,user}, host is in-ctx, so the
        #   perHost entries now bind and emit (per-user fan-out) instead of the
        #   shim's silent skip (it saw the user extra). The originals threw to
        #   assert non-emission; under the rule they DO emit, so the throws were
        #   replaced with plain strings.
        # - + "atUser perHost igloo fun", + "atUser perHost static":
        #   rule-correct. On user-aspect tux, host binds from ctx and emits at the
        #   user scope (formerly "atUser ignored …", skipped by the shim).
        expected = [
          "atHost perHost igloo fun"
          "atHost perHost igloo fun"
          "atHost perHost static"
          "atHost perHost static"
          "atHost perUser pingu@igloo fun"
          "atHost perUser static"
          "atHost perUser static"
          "atHost perUser tux@igloo fun"
          "atUser perHost igloo fun"
          "atUser perHost static"
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
          # Bare static attrsets are unconditional → emit at the home scope.
          { homeManager.funny = [ "atHome perHost static" ]; }
          # { host } fn: host is neither in-ctx nor a descendant of a standalone
          # home → misplaced → inert (IGNORED).
          (
            { host, ... }:
            {
              homeManager.funny = [ "atHome IGNORED perHost ${host.name} fun" ];
            }
          )
          { homeManager.funny = [ "atHome perUser static" ]; }
          # { user, host } fn: neither in-ctx nor descendant → inert (IGNORED).
          (
            { user, host, ... }:
            {
              homeManager.funny = [ "atHome IGNORED perUser ${user.name}@${host.name} fun" ];
            }
          )
          { homeManager.funny = [ "atHome perHome static" ]; }
          (
            { home, ... }:
            {
              homeManager.funny = [ "atHome perHome ${home.name} fun" ];
            }
          )
        ];

        expr = lib.sort lib.lessThan config.flake.homeConfigurations.tux.config.funny;
        # §6: standalone home, ctx={home}. { host }/{ user,host } fns are
        # misplaced (no host/user in ctx or as descendants) → inert. { home } fn
        # binds in-ctx. Bare static attrsets are unconditional → emit.
        #
        # FLIPS vs perCtx shim:
        # - + "atHome perHost static", + "atHome perUser static": rule-correct.
        #   These are bare static attrsets (no entity destructure) → unconditional
        #   emission at the home scope. The shim no-op'd them (it saw the home
        #   extra). Labels lost the "IGNORED" prefix since they now emit; the
        #   parametric { host }/{ user,host } fns remain genuinely inert.
        expected = [
          "atHome perHome static"
          "atHome perHome tux fun"
          "atHome perHost static"
          "atHome perUser static"
        ];
      }
    );

  };
}
