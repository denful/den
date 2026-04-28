# Tests for policy.resolve.shared — shared (non-isolated) fan-out via effect.
{ denTest, ... }:
{
  flake.tests.policy-resolve-shared = {

    # policy.resolve produces __shared = false by default.
    test-resolve-default-not-shared = denTest (
      { den, ... }:
      let
        eff = den.lib.policy.resolve { user = "tux"; };
      in
      {
        expr = {
          inherit (eff) __policyEffect __shared;
          hasValue = eff ? value;
        };
        expected = {
          __policyEffect = "resolve";
          __shared = false;
          hasValue = true;
        };
      }
    );

    # policy.resolve.shared produces __shared = true.
    test-resolve-shared-flag = denTest (
      { den, ... }:
      let
        eff = den.lib.policy.resolve.shared { user = "tux"; };
      in
      {
        expr = {
          inherit (eff) __policyEffect __shared;
          hasValue = eff ? value;
        };
        expected = {
          __policyEffect = "resolve";
          __shared = true;
          hasValue = true;
        };
      }
    );

    # Shared fan-out: aspects from the target entity kind are resolved
    # in the parent pipeline (merged state), not a sub-pipeline.
    # With shared fan-out, the target's context is merged into the parent
    # and the target's aspects see the same scope as the parent.
    test-shared-fanout-merges-state = denTest (
      { den, funnyNames, ... }:
      {
        den.schema.src.includes = [
          (
            { v }:
            {
              funny.names = [ "src-${v}" ];
            }
          )
        ];
        den.schema.tgt.includes = [
          (
            { v }:
            {
              funny.names = [ "tgt-${v}" ];
            }
          )
        ];
        den.policies.src-to-tgt = {
          to = "tgt";
          __functor =
            _:
            {
              __entityKind ? null,
              v,
              ...
            }:
            if __entityKind != "src" then [ ] else [ (den.lib.policy.resolve.shared { v = "${v}!"; }) ];
        };
        expr = funnyNames (den.lib.resolveEntity "src" { v = "x"; });
        expected = [
          "src-x"
          "tgt-x!"
        ];
      }
    );

    # Isolated fan-out (default resolve) also produces target aspects.
    # This verifies that plain resolve still works unchanged.
    test-isolated-fanout-still-works = denTest (
      { den, funnyNames, ... }:
      {
        den.schema.src2.includes = [
          (
            { v }:
            {
              funny.names = [ "src2-${v}" ];
            }
          )
        ];
        den.schema.tgt2.includes = [
          (
            { v }:
            {
              funny.names = [ "tgt2-${v}" ];
            }
          )
        ];
        den.policies.src2-to-tgt2 = {
          to = "tgt2";
          __functor =
            _:
            {
              __entityKind ? null,
              v,
              ...
            }:
            if __entityKind != "src2" then [ ] else [ (den.lib.policy.resolve { v = "${v}!"; }) ];
        };
        expr = funnyNames (den.lib.resolveEntity "src2" { v = "x"; });
        expected = [
          "src2-x"
          "tgt2-x!"
        ];
      }
    );

  };
}
