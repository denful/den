# Forward custom class to leaf option using evalConfig (parametric children variant).
{ denTest, ... }:
{
  flake.tests.deprecated.fwd-leaf-option = {

    # parametric children with evalConfig.
    test-fwd-perHost-variables = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          { den.aspects.foo.includes = lib.attrValues den.aspects.foo._; }
          {
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
                  fromAspect = _: den.lib.parametric.fixedTo { inherit host; } host.aspect;
                  evalConfig = true;
                }
              )
            ];
          }
          {
            den.aspects.foo._.sub1 = {
              variables.TEST = "test-var";
            };
          }
          {
            den.aspects.foo._.sub2 = {
              variables.OTHER = "other-var";
            };
          }
        ];

        den.aspects.igloo.includes = [ den.aspects.foo ];

        expr = {
          test = igloo.environment.sessionVariables.TEST;
          other = igloo.environment.sessionVariables.OTHER;
        };
        expected = {
          test = "test-var";
          other = "other-var";
        };
      }
    );

  };
}
