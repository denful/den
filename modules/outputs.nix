{
  lib,
  den,
  inputs,
  options,
  ...
}@args:
let
  no-flake-parts = !inputs ? flake-parts;
  # __denTest is a specialArg set by the denTest harness — its presence means
  # we are inside a test evalModules, not a real flake-parts mkFlake context.
  has-flake-parts = !no-flake-parts && !(args ? __denTest);
  flakeModule = den.lib.aspects.resolve "flake" (den.lib.resolveEntity "flake" { });
  flakeEvalConfig =
    (lib.evalModules {
      modules = [
        { _module.freeformType = lib.types.lazyAttrsOf lib.types.raw; }
        flakeModule
        inputs.den.flakeOutputs.flake
      ];
      specialArgs.inputs = inputs;
    }).config;
  flake = flakeEvalConfig.flake;
  # Keys that are internal to evalModules or already handled (flake is inherited above).
  internalKeys = [
    "_module"
    "warnings"
    "assertions"
    "flake"
  ];
  flakeRouted = builtins.removeAttrs flakeEvalConfig internalKeys;
in
{
  imports = lib.optional no-flake-parts inputs.den.flakeOutputs.flake;
  inherit flake;

  # Content routed into the flake class at paths outside config.flake
  # (e.g., route with path = ["flake-file" "inputs"]).
  den.lib.flakeRouted = flakeRouted;
}
// lib.optionalAttrs has-flake-parts {
  systems = den.systems;

  perSystem = {
    imports = [
      (den.lib.aspects.resolve "flake-parts" (den.lib.resolveEntity "flake-parts" { }))
    ];
  };
}
