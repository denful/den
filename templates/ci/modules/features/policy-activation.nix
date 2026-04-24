{ denTest, ... }:
{
  flake.tests.policy-activation = {

    # Core policies (_core = true) appear in activePoliciesFor without opt-in.
    test-core-policies-always-active = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };

        expr =
          let
            active = den.lib.synthesizePolicies.activePoliciesFor "host" { };
          in
          active ? host-to-users && active ? host-to-default;
        expected = true;
      }
    );

    # Non-core policies are excluded from activePoliciesFor by default.
    test-non-core-excluded-from-active = denTest (
      { den, ... }:
      {
        den.stages.test-act-src = {
          includes = [ ];
        };
        den.stages.test-act-tgt = {
          includes = [ ];
        };

        den.policies.test-act-src-to-tgt = {
          from = "test-act-src";
          to = "test-act-tgt";
          resolve = _: [ { } ];
        };

        expr =
          let
            active = den.lib.synthesizePolicies.activePoliciesFor "test-act-src" { };
          in
          active ? test-act-src-to-tgt;
        expected = false;
      }
    );

    # Policies in den.default.policies activates globally.
    test-default-policies-activates = denTest (
      { den, ... }:
      {
        den.stages.test-dflt-src = {
          includes = [ ];
        };
        den.stages.test-dflt-tgt = {
          includes = [ ];
        };

        den.policies.test-dflt-src-to-tgt = {
          from = "test-dflt-src";
          to = "test-dflt-tgt";
          resolve = _: [ { } ];
        };

        den.default.policies = [ "test-dflt-src-to-tgt" ];

        expr =
          let
            active = den.lib.synthesizePolicies.activePoliciesFor "test-dflt-src" { };
          in
          active ? test-dflt-src-to-tgt;
        expected = true;
      }
    );

    # Policies in den.schema.<kind>.policies flow to all entities of that kind
    # via module system merging, and activate when the entity is in context.
    test-schema-policies-activates-for-kind = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };

        den.policies.test-skind-host-pol = {
          from = "host";
          to = "user";
          resolve = _: [ { } ];
        };

        # Schema-level: applies to all hosts via module merge
        den.schema.host.policies = [ "test-skind-host-pol" ];

        # Must pass an actual host entity — schema policies merge into it
        expr =
          let
            igloo = den.hosts.x86_64-linux.igloo;
            active = den.lib.synthesizePolicies.activePoliciesFor "host" { host = igloo; };
          in
          active ? test-skind-host-pol;
        expected = true;
      }
    );

    # Schema-kind activation is scoped — host policies don't appear on users.
    test-schema-policies-scoped-to-kind = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };

        den.policies.test-scope-host-only = {
          from = "host";
          to = "user";
          resolve = _: [ { } ];
        };

        den.schema.host.policies = [ "test-scope-host-only" ];

        # Querying for "user" kind with no user entity → not active
        expr =
          let
            active = den.lib.synthesizePolicies.activePoliciesFor "user" { };
          in
          active ? test-scope-host-only;
        expected = false;
      }
    );

    # Entity-instance policies: entity.policies activates for that entity.
    test-entity-instance-policies = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          policies = [ "test-inst-host-pol" ];
        };

        den.policies.test-inst-host-pol = {
          from = "host";
          to = "user";
          resolve = _: [ { } ];
        };

        expr =
          let
            igloo = den.hosts.x86_64-linux.igloo;
            active = den.lib.synthesizePolicies.activePoliciesFor "host" { host = igloo; };
          in
          active ? test-inst-host-pol;
        expected = true;
      }
    );

    # Entity-instance policies don't leak to other entities.
    test-entity-instance-policies-scoped = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          policies = [ "test-inst-scoped-pol" ];
        };
        den.hosts.x86_64-linux.iceberg = { };

        den.policies.test-inst-scoped-pol = {
          from = "host";
          to = "user";
          resolve = _: [ { } ];
        };

        # iceberg does NOT have the policy — only igloo does.
        expr =
          let
            iceberg = den.hosts.x86_64-linux.iceberg;
            active = den.lib.synthesizePolicies.activePoliciesFor "host" { host = iceberg; };
          in
          active ? test-inst-scoped-pol;
        expected = false;
      }
    );

    # ctxSatisfies and resolveArgsSatisfied are exported and callable.
    test-exported-helpers = denTest (
      { den, ... }:
      {
        expr =
          let
            inherit (den.lib.synthesizePolicies) ctxSatisfies resolveArgsSatisfied;
            hostOk = ctxSatisfies "host" { host = { }; };
            hostBad = ctxSatisfies "host" { };
            policy = {
              resolve = { x, ... }: [ ];
            };
            argsOk = resolveArgsSatisfied policy { x = 1; };
            argsBad = resolveArgsSatisfied policy { };
          in
          [
            hostOk
            hostBad
            argsOk
            argsBad
          ];
        expected = [
          true
          false
          true
          false
        ];
      }
    );

  };
}
