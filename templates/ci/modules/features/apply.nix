{ denTest, ... }:
{
  flake.tests.ctx.test-apply = denTest (
    { den, funnyNames, ... }:
    {
      den.entityIncludes.foobar = [
        (
          { foo, bar }:
          {
            funny.names = [
              foo
              bar
            ];
          }
        )
        { funny.names = [ "owned" ]; }
      ];

      expr = funnyNames (
        den.lib.resolveEntity "foobar" {
          foo = "moo";
          bar = "baa";
        }
      );

      expected = [
        "baa"
        "moo"
        "owned"
      ];
    }
  );
}
