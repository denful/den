let
  den-lib = import ./lib;

  nixModule = inputs: { config, lib, ... }: (den-lib { inherit inputs config lib; }).nixModule;

  flakeModules.default = ./flakeModule.nix;
  flakeModules.dendritic = ./dendritic.nix;
  flakeModules.denTest = ./denTest.nix;
  flakeModules.strict = ./strict.nix;

  templates = {
    default.path = ../templates/default;
    default.description = "Default template";
    minimal.path = ../templates/minimal;
    minimal.description = "Minimalistic den";
    noflake.path = ../templates/noflake;
    noflake.description = "Den without flake";
    example.path = ../templates/example;
    example.description = "Example";
    microvm.path = ../templates/microvm;
    microvm.description = "MicroVM example";
    nvf-standalone.path = ../templates/nvf-standalone;
    nvf-standalone.description = "Standalone NVF";
    flake-parts-modules.path = ../templates/flake-parts-modules;
    flake-parts-modules.description = "flake-parts classes";
    ci.path = ../templates/ci;
    ci.description = "Feature Tests";
    bogus.path = ../templates/bogus;
    bogus.description = "For bug reproduction";
  };
in
{
  __functor = _: den-lib;
  lib = den-lib;
  namespace = import ./lib/namespace.nix;
  flakeOutputs = import ./flakeOutputs.nix;

  inherit nixModule templates;
  inherit (import ./flake-packages.nix) packages devShells;

  # flake-parts conventions
  flakeModule = flakeModules.default;
  inherit flakeModules;
  modules.flake = flakeModules;
}
