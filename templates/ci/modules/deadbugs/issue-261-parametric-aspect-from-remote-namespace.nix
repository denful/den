{ denTest, ... }:
{
  flake.tests.deadbugs-issue-261.parametric-aspect-from-remote-namespace = {

    test-explicitly-called = denTest (
      {
        lib,
        den,
        inputs,
        remote,
        funnyNames,
        ...
      }:
      let

        input =
          # evaling here is like consuming a remote flake
          (lib.evalModules {
            specialArgs.inputs = inputs;
            modules = [
              (inputs.den.flakeModule)
              (inputs.den.namespace "remote" true)
              (
                { remote, den, ... }:
                {
                  remote.parametrized =
                    { hey, ... }:
                    {
                      funny.names = [ "remote parametrized ${hey}" ];
                    };
                }
              )
            ];
          }).config.flake;
      in
      {
        imports = [ (inputs.den.namespace "remote" input) ];

        den.aspects.local.includes = [
          (remote.parametrized { hey = "you"; })
        ];

        expr = funnyNames den.aspects.local;
        expected = [ "remote parametrized you" ];
      }
    );

    test-parametric-context-passed = denTest (
      {
        lib,
        den,
        inputs,
        remote,
        funnyNames,
        ...
      }:
      let

        input =
          # evaling here is like consuming a remote flake
          (lib.evalModules {
            specialArgs.inputs = inputs;
            modules = [
              (inputs.den.flakeModule)
              (inputs.den.namespace "remote" true)
              (
                { remote, den, ... }:
                {
                  remote.parametrized =
                    { hey, ... }:
                    {
                      funny.names = [ "remote parametrized ${hey}" ];
                    };
                }
              )
            ];
          }).config.flake;
      in
      {
        imports = [ (inputs.den.namespace "remote" input) ];

        den.aspects.local.includes = [
          (
            { hey }:
            {
              funny.names = [ "local ${hey}" ];
            }
          )
          remote.parametrized # This is the bug! commenting works
        ];

        expr = funnyNames (den.aspects.local { hey = "arnold"; });
        expected = [
          "local arnold"
          "remote parametrized arnold"
        ];
      }
    );

  };
}
