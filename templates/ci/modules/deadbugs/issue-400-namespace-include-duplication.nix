{ denTest, lib, ... }:
{
  flake.tests.deadbugs-issue-400 =
    let
      module =
        { inputs, ... }:
        {
          imports = [
            inputs.den.flakeModule
            (inputs.den.namespace "test" true)
          ];

          test.aspect =
            { host }:
            {
              nixos.test = [ "aspect-${host.name}" ];
            };

          test.provided.provides.provider =
            { host }:
            {
              nixos.test = [ "provider-${host.name}" ];
            };

          test.provided.provides.included = {
            includes = [
              (
                { host }:
                {
                  nixos.test = [ "included-${host.name}" ];
                }
              )
            ];
          };
        };

      external-module =
        inputs:
        (inputs.nixpkgs.lib.evalModules {
          specialArgs = { inherit inputs; };
          modules = [ module ];
        }).config.flake;

      test-module.nixos.options.test = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    in
    {
      test-internal-namespace = denTest (
        {
          test,
          igloo,
          ...
        }:
        {
          imports = [ module ];

          den.hosts.x86_64-linux.igloo.users.tux = { };
          den.aspects.igloo.includes = [ test-module ];

          den.schema.host.includes = [
            test.aspect
            test.provided.provides.provider
            test.provided.provides.included
          ];

          expr = igloo.test;
          expected = [
            "included-igloo"
            "provider-igloo"
            "aspect-igloo"
          ];
        }
      );

      test-external-namespace = denTest (
        {
          inputs,
          test,
          igloo,
          ...
        }:
        {
          imports = [
            (inputs.den.namespace "test" [ (external-module inputs) ])
          ];

          den.hosts.x86_64-linux.igloo.users.tux = { };
          den.aspects.igloo.includes = [ test-module ];

          den.schema.host.includes = [
            test.aspect
            test.provided.provides.provider
            test.provided.provides.included
          ];

          expr = igloo.test;
          expected = [
            "included-igloo"
            "provider-igloo"
            "aspect-igloo"
          ];
        }
      );
    };
}
