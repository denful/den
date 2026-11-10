# Reported in GitHub #754, the control for its fix: a scope's own late
# registrations are exempt from late dispatch's entity-kind filter, but an
# ancestor's are not. A `{ host }` policy registered at the host fires at
# the host only, not again at each user, even when it produced nothing at
# the host (so it isn't recorded as fired there). In a full resolve
# sameInstanceAbove also keeps it there (the same host is bound above); a
# capture from a host root has no context above it, so there the filter
# alone does.
{ denTest, lib, ... }:
let
  hmUser = {
    den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
    den.aspects.tux.homeManager.home.stateVersion = "25.11";
  };
  atUserOnly = den: {
    den.policies.at-user-only =
      { host, ... }@ctx:
      lib.optional (ctx ? user) (
        den.lib.policy.include { homeManager.home.sessionVariables.LEAK = "x"; }
      );
  };
in
{
  flake.tests.deadbugs.issue-754-ancestor-host-policy-stays-at-host = {
    test-host-registered = denTest (
      { den, igloo, ... }:
      {
        imports = [
          hmUser
          (atUserOnly den)
        ];
        den.aspects.igloo.includes = [ den.policies.at-user-only ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? LEAK;
        expected = false;
      }
    );
    test-schema-host-registered = denTest (
      { den, igloo, ... }:
      {
        imports = [
          hmUser
          (atUserOnly den)
        ];
        den.schema.host.includes = [ den.policies.at-user-only ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? LEAK;
        expected = false;
      }
    );
    test-capture-from-host-root = denTest (
      { den, ... }:
      let
        root = den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; };
        captured = den.lib.capture.captureWithPaths [ "homeManager" ] root;
      in
      {
        imports = [ hmUser ];
        den.policies.at-user-only =
          { host, ... }@ctx:
          lib.optional (ctx ? user) (
            den.lib.policy.include {
              name = "leaked-at-user";
              homeManager.home.sessionVariables.LEAK = "x";
            }
          );
        den.aspects.igloo.includes = [ den.policies.at-user-only ];
        expr = (captured.pathsByClass.homeManager or { }) ? leaked-at-user;
        expected = false;
      }
    );
    # The same policy registered at the user is the user's own: it fires.
    test-user-registered-fires = denTest (
      { den, igloo, ... }:
      {
        imports = [
          hmUser
          (atUserOnly den)
        ];
        den.aspects.tux.includes = [ den.policies.at-user-only ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? LEAK;
        expected = true;
      }
    );
  };
}
