# Regression: a host's projected `host.hasAspect` must see aspects the host
# delivers DOWN to its users via `provides.to-users` — checked from inside a
# delivered home-manager aspect. Per the projected-hasAspect spec (#602), every
# in-context binding answers membership at the ACTIVE (consuming) scope. The
# id_hash re-key (e8876f3e) regressed this by keying each binding to its OWN
# bucket, so `host.hasAspect` stopped seeing provides-to-user aspects (those
# resolve under the consuming user scope). Fixed by keying all in-context
# bindings to the active scope, per spec.
#
# Reported via github.com/tschan/den-hasaspect-bug.
{ denTest, ... }:
{
  flake.tests.deadbugs.hasaspect-host-provides-to-users = {

    test-host-sees-aspect-it-provides-to-users = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.test.nixos = { };

        den.aspects.effect = {
          homeManager =
            { host, ... }:
            {
              home.username =
                if host.hasAspect den.aspects.test then lib.mkForce "right" else lib.mkForce "wrong";
            };
        };

        den.aspects.igloo = {
          provides.to-users.includes = [
            den.aspects.test
            den.aspects.effect
          ];
        };

        expr = igloo.home-manager.users.tux.home.username;
        expected = "right";
      }
    );

  };
}
