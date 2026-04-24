{ denTest, ... }:
{
  flake.tests.policy-as-field = {

    # Policy with `as` field keys synthesized output by `as`, not by `to`.
    # The `as` field is for sibling routing (e.g., host→host where the
    # context key "peer" avoids collision with the source "host" key).
    test-policy-as-renames-key = denTest (
      { den, ... }:
      {
        den.stages.test-as-source = {
          includes = [ ];
        };

        den.stages.test-as-target = {
          includes = [ ];
        };

        den.policies.test-as-source-to-target = {
          from = "test-as-source";
          to = "test-as-target";
          as = "peer";
          resolve = _: [ { } ];
        };

        # synthesize "test-as-source" should produce { peer = [{}] }, not { test-as-target = [{}] }
        expr =
          let
            intoFn = den.lib.synthesizePolicies.synthesize "test-as-source";
            result = intoFn { };
          in
          builtins.attrNames result;
        expected = [ "peer" ];
      }
    );

    # Policy without `as` field defaults key to `to`.
    test-policy-as-defaults-to-to = denTest (
      { den, ... }:
      {
        den.stages.test-as-default-source = {
          includes = [ ];
        };

        den.stages.test-as-default-target = {
          includes = [ ];
        };

        den.policies.test-as-default-source-to-target = {
          from = "test-as-default-source";
          to = "test-as-default-target";
          resolve = _: [ { } ];
        };

        # synthesize "test-as-default-source" should produce { test-as-default-target = [{}] }
        expr =
          let
            intoFn = den.lib.synthesizePolicies.synthesize "test-as-default-source";
            result = intoFn { };
          in
          builtins.attrNames result;
        expected = [ "test-as-default-target" ];
      }
    );

  };
}
