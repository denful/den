{ denTest, ... }:
{
  flake.tests.policy-inspect = {

    # inspect returns core policies matching the kind.
    test-inspect-core-policies = denTest (
      { den, lib, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
        };

        expr =
          let
            igloo = den.hosts.x86_64-linux.igloo;
            result = den.lib.policyInspect.inspect {
              kind = "host";
              context = {
                host = igloo;
              };
            };
          in
          {
            hasHostToUsers = result ? host-to-users;
            hostToUsersRouting = result.host-to-users.routing;
            hostToUsersTargetKey = result.host-to-users.targetKey;
          };
        expected = {
          hasHostToUsers = true;
          hostToUsersRouting = "child";
          hostToUsersTargetKey = "user";
        };
      }
    );

    # inspect returns resolved targets from the policy.
    test-inspect-returns-targets = denTest (
      { den, lib, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          users.alice = { };
        };

        expr =
          let
            igloo = den.hosts.x86_64-linux.igloo;
            result = den.lib.policyInspect.inspect {
              kind = "host";
              context = {
                host = igloo;
              };
            };
          in
          builtins.length result.host-to-users.targets;
        expected = 2;
      }
    );

    # All registered policies appear in inspect (no activation gating).
    test-inspect-all-policies-visible = denTest (
      { den, ... }:
      {
        den.schema.test-insp-tgt.includes = [ ];

        den.policies.test-insp-pol =
          _:
          let
            inherit (den.lib.policy) resolve;
          in
          [ (resolve.to "test-insp-tgt" { }) ];

        den.schema.test-insp-src.includes = [ den.policies.test-insp-pol ];

        expr =
          let
            result = den.lib.policyInspect.inspect {
              kind = "test-insp-src";
              context = { };
            };
          in
          result ? test-insp-pol;
        expected = true;
      }
    );

    # inspect reports sibling routing for same-type policies.
    test-inspect-sibling-routing = denTest (
      { den, ... }:
      {
        den.policies.test-insp-sibling =
          _:
          let
            inherit (den.lib.policy) resolve;
          in
          [ (resolve.to "host" { }) ];

        den.schema.host.includes = [ den.policies.test-insp-sibling ];

        den.hosts.x86_64-linux.igloo = { };

        expr =
          let
            igloo = den.hosts.x86_64-linux.igloo;
            result = den.lib.policyInspect.inspect {
              kind = "host";
              context = {
                host = igloo;
              };
            };
          in
          {
            routing = result.test-insp-sibling.routing;
            targetKey = result.test-insp-sibling.targetKey;
          };
        expected = {
          routing = "sibling";
          targetKey = "host";
        };
      }
    );

  };
}
