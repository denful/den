{ denTest, ... }:
{
  flake.tests.policies = {

    test-policy-fires = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.test-rel-target.includes = [ ];

        den.policies.host-to-test-rel = {
          from = "host";
          to = "test-rel-target";
          __functor =
            _: _:
            let
              inherit (den.lib.policy) include;
            in
            [
              (include { nixos.users.users.tux.description = "from-rel-target-stage"; })
            ];
        };

        den.default.policies = [ "host-to-test-rel" ];

        expr = igloo.users.users.tux.description;
        expected = "from-rel-target-stage";
      }
    );

    # Both a policy target stage and an into transition contribute
    # to the resolved NixOS config without clobbering each other.
    test-policy-coexists-with-into = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.test-rel-coexist.includes = [ ];

        den.default.nixos.users.users.tux.description = "from-default-stage";

        den.policies.host-to-test-rel-coexist = {
          from = "host";
          to = "test-rel-coexist";
          __functor =
            _: _:
            let
              inherit (den.lib.policy) include;
            in
            [
              (include { nixos.networking.hostName = "from-rel-stage"; })
            ];
        };

        den.default.policies = [ "host-to-test-rel-coexist" ];

        expr = [
          igloo.networking.hostName
          igloo.users.users.tux.description
        ];
        expected = [
          "from-rel-stage"
          "from-default-stage"
        ];
      }
    );

    # Policy with handlers field is accepted without error.
    # Policy's handlers are scoped into the transition resolution.
    # A parametric aspect under the transition can query the handler via bind.fn.
    test-policy-handler-scoped = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.test-scoped.includes = [ ];

        den.default.policies = [ "host-to-test-scoped" ];

        den.policies.host-to-test-scoped = {
          from = "host";
          to = "test-scoped";
          resolve = _: [ { } ];
          aspects = [
            (
              { test-greet, ... }:
              {
                nixos.users.users.tux.description = test-greet;
              }
            )
          ];
          handlers.test-greet =
            {
              param,
              state,
            }:
            {
              resume = "hello-from-policy";
              inherit state;
            };
        };

        expr = igloo.users.users.tux.description;
        expected = "hello-from-policy";
      }
    );

    test-policy-with-handlers = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.test-handler-target.includes = [ ];

        den.default.policies = [ "host-to-test-handler" ];

        den.policies.host-to-test-handler = {
          from = "host";
          to = "test-handler-target";
          resolve = _: [ { } ];
          aspects = [
            { nixos.users.users.tux.description = "handler-target"; }
          ];
          handlers.test-effect =
            {
              param,
              state,
            }:
            {
              resume = "test-value";
              inherit state;
            };
        };

        expr = igloo.users.users.tux.description;
        expected = "handler-target";
      }
    );

  };
}
