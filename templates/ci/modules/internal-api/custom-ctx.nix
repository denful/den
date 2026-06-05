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
        den.schema.shout.includes = [ ];
        den.policies.test-greeting-to-shout =
          { hello, ... }:
          let
            inherit (den.lib.policy) resolve include;
          in
          [
            (resolve.to "shout" { shout = lib.toUpper hello; })
            (include (
              { shout }:
              {
                funny.names = [ shout ];
              }
            ))
          ];
        den.schema.greeting.includes = [
          (
            { hello }:
            {
              funny.names = [ hello ];
            }
          )
          den.policies.test-greeting-to-shout
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
        den.schema.foo.includes = [
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
        den.schema.bar.includes = [
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
