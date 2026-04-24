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
        den.stages.greeting.provides.greeting =
          { hello }:
          {
            funny.names = [ hello ];
          };
        den.policies.test-greeting-to-shout = {
          from = "greeting";
          to = "shout";
          resolve = ctx: if !(ctx ? hello) then [ ] else [ { shout = lib.toUpper ctx.hello; } ];
        };
        den.default.policies = [ "test-greeting-to-shout" ];

        den.stages.shout.provides.shout =
          { shout }:
          {
            funny.names = [ shout ];
          };

        expr = funnyNames (den.lib.resolveStage "greeting" { hello = "world"; });
        expected = [
          "WORLD"
          "world"
        ];
      }
    );

    test-ctx-includes-static-and-parametric = denTest (
      { den, funnyNames, ... }:
      {
        den.stages.foo.provides.foo =
          { foo }:
          {
            funny.names = [ foo ];
          };
        den.stages.foo.includes = [
          { funny.names = [ "static-include" ]; }
          (
            { foo, ... }:
            {
              funny.names = [ "param-${foo}" ];
            }
          )
        ];

        expr = funnyNames (den.lib.resolveStage "foo" { foo = "hello"; });
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
        den.stages.bar.provides.bar =
          { x }:
          {
            funny.names = [ x ];
          };
        den.stages.bar.funny.names = [ "owned" ];
        den.stages.bar.includes = [ ];

        expr = funnyNames (den.lib.resolveStage "bar" { x = "val"; });
        expected = [
          "owned"
          "val"
        ];
      }
    );

  };
}
