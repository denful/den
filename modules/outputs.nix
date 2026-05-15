{
  lib,
  den,
  inputs,
  ...
}@args:
let
  # Two guards with different semantics:
  # - no-flake-parts: controls flakeOutputs import (purely based on inputs)
  # - has-flake-parts: controls perSystem injection (also excludes denTest,
  #   where inputs ? flake-parts can be true but perSystem doesn't exist;
  #   checking options ? perSystem instead would cause infinite recursion)
  no-flake-parts = !inputs ? flake-parts;
  has-flake-parts = !no-flake-parts && !(args ? __denTest);
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
// lib.optionalAttrs has-flake-parts {
  systems = den.systems;

  perSystem = {
    imports = [
      (den.lib.aspects.resolve "flake-parts" (den.lib.resolveEntity "flake-parts" { }))
    ];
  };
}
