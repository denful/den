{ denTest, ... }:
{
  flake.tests.empty-aspects = {
    test-no-aspects = denTest (
      { den, ... }:
      {
        expr = den.aspects;
        expected = { };
      }
    );
  };
}
