{ denTest, ... }:
{
  flake.tests.ctx.test-apply = denTest (
    { den, funnyNames, ... }:
    {
      den.stages.foobar.provides.foobar =
        { foo, bar }:
        {
          funny.names = [
            foo
            bar
          ];
        };

      den.stages.foobar.funny.names = [ "owned" ];
      den.stages.foobar.includes = [ ];

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
