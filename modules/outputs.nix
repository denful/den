{
  lib,
  den,
  inputs,
  ...
}@args:
let
  has-flake-parts = args ? flake-parts-lib;
  flakeModule = den.lib.aspects.resolve "flake" (den.lib.resolveEntity "flake" { });
  flake =
    (lib.evalModules {
      modules = [
        flakeModule
        inputs.den.flakeOutputs.flake
      ];
      specialArgs.inputs = inputs;
    }).config.flake;
in
{
  imports = lib.optional (!(inputs ? flake-parts)) inputs.den.flakeOutputs.flake;
  inherit flake;
}
// lib.optionalAttrs has-flake-parts {
  systems = den.systems;

  perSystem = {
    imports = [
      (den.lib.aspects.resolve "flake-parts" (den.lib.resolveEntity "flake-parts" { }))
    ];
  };
}
