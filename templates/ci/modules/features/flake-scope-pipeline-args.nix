{ denTest, ... }:
{
  flake.tests.flake-scope-pipeline-args = {

    # pipelineOnly on attrset preserves all attributes and adds collisionPolicy.
    test-pipeline-only-preserves-attrs = denTest (
      { den, ... }:
      let
        original = {
          mkIf = cond: val: if cond then val else { };
          foo = "bar";
        };
        tagged = den.lib.policy.pipelineOnly original;
      in
      {
        expr = {
          preservesFoo = tagged.foo;
          preservesMkIf = (tagged.mkIf true "yes");
          hasPolicy = tagged.collisionPolicy;
        };
        expected = {
          preservesFoo = "bar";
          preservesMkIf = "yes";
          hasPolicy = "class-wins";
        };
      }
    );

    # pipelineOnly on non-attrset (function) wraps with __functor.
    test-pipeline-only-non-attrset = denTest (
      { den, ... }:
      let
        fn = x: x + 1;
        tagged = den.lib.policy.pipelineOnly fn;
      in
      {
        expr = {
          callable = tagged 5;
          hasPolicy = tagged.collisionPolicy;
          isAttrs = builtins.isAttrs tagged;
        };
        expected = {
          callable = 6;
          hasPolicy = "class-wins";
          isAttrs = true;
        };
      }
    );

  };
}
