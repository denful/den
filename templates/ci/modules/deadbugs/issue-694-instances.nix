# Issue #694 §11a R2 and R3: a policy fires once per instance, whatever its
# body returns, and a receiver-less effect from a host policy is aimed at the
# host only when it targets the host's class.
{ denTest, lib, ... }:
let
  hmUser = {
    den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
    den.aspects.tux.homeManager.home.stateVersion = "25.11";
  };
in
{
  flake.tests.deadbugs.issue-694-instances = {

    # O1: a no-argument policy has one instance, at its registrant. Its body is
    # empty there, so it fires nowhere. Under effect-dependent firing it fired
    # again at tux, where it is not empty.
    test-no-arg-policy-fires-once = denTest (
      { den, igloo, ... }:
      lib.recursiveUpdate hmUser {
        den.policies.ctx-branch =
          ctx:
          lib.optional (ctx ? user) (den.lib.policy.include { homeManager.home.sessionVariables.O1 = "x"; });
        den.aspects.igloo.includes = [ den.policies.ctx-branch ];
        expr = igloo.home-manager.users.tux.home.sessionVariables.O1 or "<missing>";
        expected = "<missing>";
      }
    );

    # The same for a `{ host }` policy empty at the host: one instance, there.
    # This pins main's outcome only: the late pass's entity-kind filter already
    # keeps a `{ host }` policy from re-firing at a user scope.
    test-host-policy-empty-at-host-fires-once = denTest (
      { den, igloo, ... }:
      lib.recursiveUpdate hmUser {
        den.policies.host-branch =
          { host, ... }@ctx:
          lib.optional (ctx ? user) (den.lib.policy.include { homeManager.home.sessionVariables.H = "x"; });
        den.aspects.igloo.includes = [ den.policies.host-branch ];
        expr = igloo.home-manager.users.tux.home.sessionVariables.H or "<missing>";
        expected = "<missing>";
      }
    );

    # A deliver-guest-shaped policy (`{ ... }@args`, guarded) fires at its
    # registrant and delivers once.
    test-deliver-guest-shape-once = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.dg = den.lib.policy.mkPolicy "dg" (
          { ... }@args:
          lib.optionals (!(args ? user) && !(args ? home)) [
            (den.lib.policy.provide {
              class = "nixos";
              module.boot.kernelModules = [ "dg-mod" ];
            })
          ]
        );
        den.aspects.igloo.includes = [ den.policies.dg ];
        expr = builtins.filter (m: m == "dg-mod") igloo.boot.kernelModules;
        expected = [ "dg-mod" ];
      }
    );

    # R3: a host-registered receiver-less route into a user-side class stays
    # where it fired, the user.
    test-host-route-into-user-class-stays = denTest (
      { den, igloo, ... }:
      lib.recursiveUpdate hmUser {
        den.classes.srcHm.description = "a user-side source class";
        den.policies.src-to-hm =
          { host, user, ... }:
          [
            (den.lib.policy.route {
              fromClass = "srcHm";
              intoClass = "homeManager";
              path = [ ];
            })
          ];
        den.aspects.igloo.includes = [ den.policies.src-to-hm ];
        den.aspects.tux.srcHm.home.sessionVariables.ROUTED = "yes";
        expr = igloo.home-manager.users.tux.home.sessionVariables.ROUTED or "<missing>";
        expected = "yes";
      }
    );

    # R3: one into the host's class reaches the host.
    test-host-route-into-host-class-reaches-host = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.classes.srcOs.description = "a user-authored source class";
        den.policies.src-to-nixos =
          { host, user, ... }:
          [
            (den.lib.policy.route {
              fromClass = "srcOs";
              intoClass = "nixos";
              path = [ ];
            })
          ];
        den.aspects.igloo.includes = [ den.policies.src-to-nixos ];
        den.aspects.tux.srcOs.environment.etc.routed.text = "yes";
        expr = igloo.environment.etc.routed.text or "<missing>";
        expected = "yes";
      }
    );
  };
}
