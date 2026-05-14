{
  lib,
  den,
  inputs,
  ...
}@args:
let
  no-flake-parts = !inputs ? flake-parts;
  # __denTest is a specialArg set by the denTest harness — its presence means
  # we are inside a test evalModules, not a real flake-parts mkFlake context.
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
