{ denTest, ... }:
{
  flake.tests.ctx-custom = {

    test-ctx-into = denTest (
      {
        den,
        lib,
        funnyNames,
        ...
      }:
      {
        den.entityIncludes.greeting = [
          (
            { hello }:
            {
              funny.names = [ hello ];
            }
          )
        ];
        den.policies.test-greeting-to-shout = {
          from = "greeting";
          to = "shout";
          resolve = ctx: if !(ctx ? hello) then [ ] else [ { shout = lib.toUpper ctx.hello; } ];
        };
        den.default.policies = [ "test-greeting-to-shout" ];

        den.entityIncludes.shout = [
          (
            { shout }:
            {
              funny.names = [ shout ];
            }
          )
        ];

        expr = funnyNames (den.lib.resolveEntity "greeting" { hello = "world"; });
        expected = [
          "WORLD"
          "world"
        ];
      }
    );

    test-ctx-includes-static-and-parametric = denTest (
      { den, funnyNames, ... }:
      {
        den.entityIncludes.foo = [
          (
            { foo }:
            {
              funny.names = [ foo ];
            }
          )
          { funny.names = [ "static-include" ]; }
          (
            { foo, ... }:
            {
              funny.names = [ "param-${foo}" ];
            }
          )
        ];

        expr = funnyNames (den.lib.resolveEntity "foo" { foo = "hello"; });
        expected = [
          "hello"
          "param-hello"
          "static-include"
        ];
      }
    );

    test-ctx-owned = denTest (
      { den, funnyNames, ... }:
      {
        den.entityIncludes.bar = [
          (
            { x }:
            {
              funny.names = [ x ];
            }
          )
          { funny.names = [ "owned" ]; }
        ];

        expr = funnyNames (den.lib.resolveEntity "bar" { x = "val"; });
        expected = [
          "owned"
          "val"
        ];
      }
    );

  };
}
