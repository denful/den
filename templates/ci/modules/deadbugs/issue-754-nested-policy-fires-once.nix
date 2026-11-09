# Reported in GitHub #754: a nested policy reaching a user through more than
# one path fires once there.
{ denTest, lib, ... }:
let
  hmUser = {
    den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
    den.aspects.tux.homeManager.home.stateVersion = "25.11";
  };
  # A `{ host }` policy nested in an aspect, adding to a list option, so a
  # second firing shows as a second entry.
  nested = den: {
    den.policies.g =
      { host, ... }: [ (den.lib.policy.include { nixos.boot.kernelModules = [ "g" ]; }) ];
    den.aspects.carrier.includes = [ den.policies.g ];
  };
  twoHm = {
    den.hosts.x86_64-linux.igloo.users = {
      tux.classes = [ "homeManager" ];
      pingu.classes = [ "homeManager" ];
    };
    den.aspects.tux.homeManager.home.stateVersion = "25.11";
    den.aspects.pingu.homeManager.home.stateVersion = "25.11";
  };
  count = igloo: builtins.length (builtins.filter (m: m == "g") igloo.boot.kernelModules);
in
{
  flake.tests.deadbugs.issue-754-nested-policy-fires-once = {
    test-direct-and-to-users = denTest (
      { den, igloo, ... }:
      {
        imports = [
          hmUser
          (nested den)
        ];
        den.internal.transitionDefaults = lib.mkForce true;
        den.aspects.tux.includes = [ den.aspects.carrier ];
        den.aspects.dev.provides.to-users.includes = [ den.aspects.carrier ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = count igloo;
        expected = 1;
      }
    );
    test-to-users-and-host-policy = denTest (
      { den, igloo, ... }:
      {
        imports = [
          hmUser
          (nested den)
        ];
        den.internal.transitionDefaults = lib.mkForce true;
        den.aspects.dev.provides.to-users.includes = [ den.aspects.carrier ];
        den.policies.hp = { host, user, ... }: [ (den.lib.policy.include den.aspects.carrier) ];
        den.aspects.igloo.includes = [
          den.aspects.dev
          den.policies.hp
        ];
        expr = count igloo;
        expected = 1;
      }
    );
    # Registered on the host and carried late to both users through
    # to-users, in the transition and the end state: once.
    test-host-and-to-users-two-users = denTest (
      { den, igloo, ... }:
      {
        imports = [
          twoHm
          (nested den)
        ];
        den.internal.transitionDefaults = lib.mkForce true;
        den.aspects.dev.provides.to-users.includes = [ den.aspects.carrier ];
        den.aspects.igloo.includes = [
          den.aspects.dev
          den.aspects.carrier
        ];
        expr = count igloo;
        expected = 1;
      }
    );
    test-host-and-to-users-two-users-end-state = denTest (
      { den, igloo, ... }:
      {
        imports = [
          twoHm
          (nested den)
        ];
        den.aspects.dev.provides.to-users.includes = [ den.aspects.carrier ];
        den.aspects.igloo.includes = [
          den.aspects.dev
          den.aspects.carrier
        ];
        expr = count igloo;
        expected = 1;
      }
    );
    # The same, captured from the host root: a user-gated policy registered on
    # the host and carried late to tux doesn't leak into tux.
    test-host-and-to-users-capture = denTest (
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
        den.aspects.carrier.includes = [ den.policies.at-user-only ];
        den.aspects.dev.provides.to-users.includes = [ den.aspects.carrier ];
        den.aspects.igloo.includes = [
          den.policies.at-user-only
          den.aspects.dev
        ];
        expr = (captured.pathsByClass.homeManager or { }) ? leaked-at-user;
        expected = false;
      }
    );
    # Control: through to-users alone it fires.
    test-to-users-alone = denTest (
      { den, igloo, ... }:
      {
        imports = [
          hmUser
          (nested den)
        ];
        den.internal.transitionDefaults = lib.mkForce true;
        den.aspects.dev.provides.to-users.includes = [ den.aspects.carrier ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = count igloo;
        expected = 1;
      }
    );
  };
}
