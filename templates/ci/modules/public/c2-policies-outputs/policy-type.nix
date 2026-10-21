{ denTest, ... }:
{
  flake.tests.policy-type = {

    test-raw-fn-wrapping = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.h.users.u = { };
        den.policies.my-policy = _: [ ];
        den.aspects.h = { };
        expr = {
          isPolicy = den.policies.my-policy.__isPolicy;
          name = den.policies.my-policy.name;
          isFn = builtins.isFunction den.policies.my-policy.fn;
        };
        expected = {
          isPolicy = true;
          name = "my-policy";
          isFn = true;
        };
      }
    );

    test-prewrapped-passthrough = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.h.users.u = { };
        den.policies.wrapped = {
          __isPolicy = true;
          name = "original";
          fn = _: [ ];
        };
        den.aspects.h = { };
        expr = den.policies.wrapped.__isPolicy;
        expected = true;
      }
    );

  };
}
