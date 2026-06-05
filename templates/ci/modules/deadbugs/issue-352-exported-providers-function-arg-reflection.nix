{ denTest, ... }:
{
  flake.tests.deadbugs-issue-352 =
    let
      module =
        { inputs, ... }:
        {
          imports = [
            inputs.den.flakeModule
            (inputs.den.namespace "test" true)
          ];

          test.aspect.provides.host =
            { host, ... }:
            {
              nixos.environment.sessionVariables.TEST_HOST = host.name;
            };
        };
      internal = module;
      external =
        inputs:
        (inputs.nixpkgs.lib.evalModules {
          specialArgs = { inherit inputs; };
          modules = [ module ];
        }).config.flake;
    in
    {
      test-internal-exported-providers-function-arg-reflection = denTest (
        {
          lib,
          test,
          ...
        }:
        {
          imports = [ internal ];

          expr = lib.functionArgs test.aspect.provides.host;
          expected = {
            host = false;
          };
        }
      );

      test-raw-exported-providers-function-arg-reflection = denTest (
        {
          inputs,
          lib,
          test,
          ...
        }:
        {
          expr = lib.functionArgs (external inputs).denful.test.aspect.provides.host;
          expected = {
            host = false;
          };
        }
      );

      test-external-exported-providers-function-arg-reflection = denTest (
        {
          inputs,
          test,
          lib,
          ...
        }:

        {
          imports = [ (inputs.den.namespace "test" [ (external inputs) ]) ];

          expr = lib.functionArgs test.aspect.provides.host;
          expected = {
            host = false;
          };
        }
      );
    };
}
