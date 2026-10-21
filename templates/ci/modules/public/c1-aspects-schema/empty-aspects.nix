{ denTest, ... }:
{
  flake.tests.c1.empty-aspects = {
    test-no-aspects = denTest (
      { den, ... }:
      {
        expr = den.aspects;
        expected = { };
      }
    );
  };
}
