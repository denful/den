# Regression: nested aspect keys with multiple definitions should merge
# (collect all class modules), not last-win overwrite.
{
  denTest,
  lib,
  ...
}:
{
  flake.tests.deadbugs.nested-aspect-merge = {

    # Two modules defining den.aspects.system.base.nixos should both contribute.
    # Before the fix, only the last definition survived (last-win via //).
    test-multi-def-nested-class-key = denTest (
      { den, igloo, ... }:
      {
        imports = [
          # Module A
          { den.aspects.igloo.base.nixos.environment.variables.FROM_A = "yes"; }
          # Module B
          { den.aspects.igloo.base.nixos.environment.variables.FROM_B = "yes"; }
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.aspects.igloo.base ];

        expr = {
          hasA = igloo.environment.variables ? FROM_A;
          hasB = igloo.environment.variables ? FROM_B;
        };
        expected = {
          hasA = true;
          hasB = true;
        };
      }
    );

  };
}
