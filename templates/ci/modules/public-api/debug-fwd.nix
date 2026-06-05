# Forward custom class to leaf option using evalConfig.
{ denTest, ... }:
{
  flake.tests.fwd-leaf-option = {

    # Forward a custom "variables" class to environment.sessionVariables.
    test-fwd-variables-static = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.variables.TEST = "test-var";

        den.schema.host.includes = [
          (
            { host, ... }:
            den._.forward {
              each = [ "nixos" ];
              fromClass = _: "variables";
              intoClass = _: host.class;
              intoPath = _: [
                "environment"
                "sessionVariables"
              ];
              fromAspect = _: host.aspect;
              evalConfig = true;
            }
          )
        ];

        expr = igloo.environment.sessionVariables.TEST;
        expected = "test-var";
      }
    );

  };
}
