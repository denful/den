# Regression: a host-class module in den.default that takes `user` was lost
# from a host that accepts that user (the transition default, or an explicit
# user-aspects). The host's per-user copy was dropped as a duplicate of the
# user's own copy, by a key the two share, so both went. Worked before the
# class-level fan-out. Reported in Matrix.
{ denTest, lib, ... }:
let
  cell =
    {
      transitionDefaults ? true,
      acknowledged ? false,
      explicit ? false,
      users ? [ "admin" ],
    }:
    denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce transitionDefaults;
        den.migrations.user-host-content.acknowledged = acknowledged;
        den.schema.user.classes = lib.mkForce [ "user" ];
        den.schema.host.includes = lib.optional explicit den.batteries.user-aspects;
        den.hosts.x86_64-linux.igloo.users = lib.genAttrs users (_: { });
        den.aspects.kanata.nixos =
          { user, ... }:
          {
            environment.etc."kanata-${user.userName}".text = "on";
            users.groups.uinput.members = [ user.userName ];
          };
        den.default.includes = [
          den.batteries.define-user
          den.aspects.kanata
        ];
        expr = [
          (map (u: igloo.environment.etc."kanata-${u}".text or null) users)
          igloo.users.groups.uinput.members
        ];
        expected = [
          (map (_: "on") users)
          users
        ];
      }
    );
in
{
  flake.tests.accepted-user-class-fan = {
    test-transition-default = cell { };
    test-transition-two-users = cell {
      users = [
        "admin"
        "guest"
      ];
    };
    test-explicit-user-aspects = cell {
      transitionDefaults = false;
      explicit = true;
    };
    test-explicit-acknowledged = cell {
      acknowledged = true;
      explicit = true;
    };
    # Controls: no acceptance, so the host's own copy is the only one.
    test-acknowledged = cell { acknowledged = true; };
    test-end-state = cell { transitionDefaults = false; };
  };
}
