# Nested sub-aspects are never auto-walked — they require explicit includes.
# This is the fix for the original bug where including den.aspects.root.a
# still auto-walked sibling b.
{
  denTest,
  lib,
  ...
}:
{
  flake.tests.deadbugs.nested-includes-scoping = {

    # Only explicitly included sub-aspects emit
    test-nested-includes-scoping = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.root ];

        den.aspects.root = {
          includes = [ den.aspects.root.a ];

          a.nixos.environment.variables.FROM_A = "yes";
          b.nixos.environment.variables.FROM_B = "yes";
        };

        expr = {
          hasA = igloo.environment.variables ? FROM_A;
          hasB = igloo.environment.variables ? FROM_B;
        };
        expected = {
          hasA = true;
          hasB = false;
        };
      }
    );

    # Provides equivalent still works
    test-provides-includes-scoping = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.root ];

        den.aspects.root = {
          includes = [ den.aspects.root.a ];

          provides.a.nixos.environment.variables.FROM_A = "yes";
          provides.b.nixos.environment.variables.FROM_B = "yes";
        };

        expr = {
          hasA = igloo.environment.variables ? FROM_A;
          hasB = igloo.environment.variables ? FROM_B;
        };
        expected = {
          hasA = true;
          hasB = false;
        };
      }
    );

    # Without includes, nested keys do NOT auto-walk
    test-nested-no-auto-walk = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.root ];

        den.aspects.root = {
          a.nixos.environment.variables.FROM_A = "yes";
          b.nixos.environment.variables.FROM_B = "yes";
        };

        expr = {
          hasA = igloo.environment.variables ? FROM_A;
          hasB = igloo.environment.variables ? FROM_B;
        };
        expected = {
          hasA = false;
          hasB = false;
        };
      }
    );

    # External includes don't activate nested keys
    test-external-includes-no-auto-walk = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.root ];

        den.aspects.ext.nixos.environment.variables.FROM_EXT = "yes";

        den.aspects.root = {
          includes = [ den.aspects.ext ];

          a.nixos.environment.variables.FROM_A = "yes";
          b.nixos.environment.variables.FROM_B = "yes";
        };

        expr = {
          hasA = igloo.environment.variables ? FROM_A;
          hasB = igloo.environment.variables ? FROM_B;
          hasExt = igloo.environment.variables ? FROM_EXT;
        };
        expected = {
          hasA = false;
          hasB = false;
          hasExt = true;
        };
      }
    );
  };
}
