# Regression: including a nested aspect should NOT auto-include its
# sub-aspects.  den.aspects.apps.dev-tools.foo should only be included
# when explicitly referenced, not when only <apps/dev-tools> is included.
# https://github.com/denful/den/issues/XXX
{
  denTest,
  lib,
  ...
}:
{
  flake.tests.deadbugs.nested-aspect-includes = {

    # Including dev-tools should NOT pull in dev-tools.foo
    test-nested-sub-aspect-not-auto-included = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.apps.dev-tools = {
          nixos.environment.variables.DEV_TOOLS = "yes";
        };

        den.aspects.apps.dev-tools.foo = {
          nixos.environment.variables.DEV_TOOLS_FOO = "yes";
        };

        # Include only dev-tools, not foo
        den.aspects.igloo.includes = [ den.aspects.apps.dev-tools ];

        expr = {
          hasDevTools = igloo.environment.variables.DEV_TOOLS == "yes";
          # foo should NOT be included
          hasFoo = igloo.environment.variables ? DEV_TOOLS_FOO;
        };
        expected = {
          hasDevTools = true;
          hasFoo = false;
        };
      }
    );

    # Explicitly including the sub-aspect should work
    test-nested-sub-aspect-explicit-include = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.apps.dev-tools = {
          nixos.environment.variables.DEV_TOOLS = "yes";
        };

        den.aspects.apps.dev-tools.foo = {
          nixos.environment.variables.DEV_TOOLS_FOO = "yes";
        };

        # Include both explicitly
        den.aspects.igloo.includes = [
          den.aspects.apps.dev-tools
          den.aspects.apps.dev-tools.foo
        ];

        expr = {
          hasDevTools = igloo.environment.variables.DEV_TOOLS == "yes";
          hasFoo = igloo.environment.variables.DEV_TOOLS_FOO == "yes";
        };
        expected = {
          hasDevTools = true;
          hasFoo = true;
        };
      }
    );

  };
}
