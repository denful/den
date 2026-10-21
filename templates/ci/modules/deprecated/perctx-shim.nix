# Compat-shim regression test: the RESTORED den.lib.perHost / perUser / perHome
# aliases (modules/context/perHost-perUser.nix). Proves the API still resolves
# and delivers the CURRENT binding rule (bind-at-scope / class-local fan-out),
# i.e. it is a faithful alias for a plain `{ host, ... }:` function — NOT the
# old self-suppressing guard. (The plain-function equivalents are asserted in
# `perUser-perHost.nix`; this asserts the shim produces the same result.)
{ denTest, ... }:
{
  flake.tests.deprecated.perctx-shim = {

    test-perhost-binds-once-peruser-fans-out = denTest (
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

        # Included at the HOST aspect scope (ctx = { host }).
        den.aspects.igloo.includes = [
          # perHost: requires `host`, in-ctx at host scope → binds ONCE.
          (den.lib.perHost (
            { host, ... }:
            {
              nixos.funny = [ "perHost ${host.name}" ];
            }
          ))
          # perUser: requires `host` + `user`; `user` is a descendant entity at
          # the host scope → class-local fan-out per user (tux, pingu). The old
          # shim would have self-suppressed here (saw the deeper `user` key);
          # the restored shim delivers the rule-correct per-user fan-out.
          (den.lib.perUser (
            { host, user, ... }:
            {
              nixos.funny = [ "perUser ${user.name}@${host.name}" ];
            }
          ))
        ];

        expr = lib.sort lib.lessThan igloo.funny;
        expected = [
          "perHost igloo"
          "perUser pingu@igloo"
          "perUser tux@igloo"
        ];
      }
    );
  };
}
