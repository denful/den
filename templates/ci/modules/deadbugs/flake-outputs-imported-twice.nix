# Each of den's flake output modules (`den.flakeOutputs.<output>`, and
# `den.flakeOutputs.flake`) carries a key, so importing it from two files
# declares its option once and both files' definitions merge: nixpkgs counts
# an unkeyed module once per importing file.
{ inputs, ... }:
let
  # Two importers, as two files would be: two separate module values.
  importer = system: name: {
    imports = [ inputs.den.flakeOutputs.packages ];
    config.flake.packages.${system}.${name} = name;
  };
  eval =
    modules:
    (inputs.nixpkgs.lib.evalModules {
      modules = [ inputs.den.flakeOutputs.flake ] ++ modules;
    }).config.flake.packages;
in
{
  flake.tests.flake-outputs-imported-twice = {
    test-flake-module-two-importers = {
      expr =
        (inputs.nixpkgs.lib.evalModules {
          modules = [
            {
              imports = [ inputs.den.flakeOutputs.flake ];
              config.flake.x = 1;
            }
            {
              imports = [ inputs.den.flakeOutputs.flake ];
              config.flake.y = 2;
            }
          ];
        }).config.flake;
      expected = {
        x = 1;
        y = 2;
      };
    };

    test-two-importers-declare-once = {
      expr = eval [
        (importer "x86_64-linux" "a")
        (importer "x86_64-linux" "b")
      ];
      expected = {
        x86_64-linux = {
          a = "a";
          b = "b";
        };
      };
    };
  };
}
