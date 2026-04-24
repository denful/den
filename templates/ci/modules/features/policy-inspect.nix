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
            hasHostToDefault = result ? host-to-default;
            hostToUsersRouting = result.host-to-users.routing;
            hostToUsersTargetKey = result.host-to-users.targetKey;
          };
        expected = {
          hasHostToUsers = true;
          hasHostToDefault = true;
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

    # inspect only returns active policies.
    test-inspect-respects-activation = denTest (
      { den, ... }:
      {
        den.stages.test-insp-src = {
          includes = [ ];
        };
        den.stages.test-insp-tgt = {
          includes = [ ];
        };

        den.policies.test-insp-inactive = {
          from = "test-insp-src";
          to = "test-insp-tgt";
          resolve = _: [ { } ];
        };

        # Not activated — should not appear in inspect
        expr =
          let
            result = den.lib.policyInspect.inspect {
              kind = "test-insp-src";
              context = { };
            };
          in
          result ? test-insp-inactive;
        expected = false;
      }
    );

    # inspect shows activated policy.
    test-inspect-shows-activated = denTest (
      { den, ... }:
      {
        den.stages.test-insp-act-src = {
          includes = [ ];
        };
        den.stages.test-insp-act-tgt = {
          includes = [ ];
        };

        den.policies.test-insp-act-pol = {
          from = "test-insp-act-src";
          to = "test-insp-act-tgt";
          resolve = _: [ { } ];
        };

        den.default.policies = [ "test-insp-act-pol" ];

        expr =
          let
            result = den.lib.policyInspect.inspect {
              kind = "test-insp-act-src";
              context = { };
            };
          in
          result ? test-insp-act-pol;
        expected = true;
      }
    );

    # inspect reports sibling routing for same-type policies.
    test-inspect-sibling-routing = denTest (
      { den, ... }:
      {
        den.policies.test-insp-sibling = {
          _core = true;
          from = "host";
          to = "host";
          as = "peer";
          resolve = _: [ { } ];
        };

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
            as = result.test-insp-sibling.as;
          };
        expected = {
          routing = "sibling";
          targetKey = "peer";
          as = "peer";
        };
      }
    );

  };
}
