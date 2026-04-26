{
  lib,
  den,
  inputs,
  ...
}:
let
  no-flake-parts = !inputs ? flake-parts;
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
  imports = lib.optional no-flake-parts inputs.den.flakeOutputs.flake;
  inherit flake;
}
