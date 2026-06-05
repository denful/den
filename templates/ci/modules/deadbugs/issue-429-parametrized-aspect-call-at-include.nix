# Minimal reproduction of drupol's pattern from issue #429
# A factory-function aspect called at include time, returning nixos config.
{ denTest, ... }:
{
  flake.tests.deadbugs-issue-429 = {

    test-parametrized-aspect-call-at-include = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.facter = reportPath: {
              nixos.environment.variables.FACTER_REPORT = reportPath;
            };
          }
          {
            den.aspects.igloo.includes = [ (den.aspects.facter "/path/to/report") ];
          }
        ];

        expr = igloo.environment.variables.FACTER_REPORT or null;
        expected = "/path/to/report";
      }
    );

  };
}
