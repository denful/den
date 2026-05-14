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
  # Bridge module: injects routed flake content into top-level flake-parts
  # options. Takes a list of top-level key names to bridge from the inner
  # flake eval. Keys must be passed from outside the module system (at import
  # time) because the NixOS module system requires static key enumeration.
  #
  # Usage:
  #   imports = [ (inputs.den.flakeModule ["flake-file"]) ];
  # Or separately:
  #   imports = [ inputs.den.flakeModule (inputs.den.flakeBridge ["flake-file"]) ];
  flakeBridge =
    bridgeKeysOrNull:
    {
      den,
      lib,
      options,
      ...
    }:
    let
      routed = den.lib.flakeRouted or { };
      internalKeys = [
        "_module"
        "warnings"
        "assertions"
        "flake"
        "den"
        "perSystem"
        "systems"
      ];
      # When no keys specified, derive from outer options (config-free).
      bridgeKeys =
        if bridgeKeysOrNull != null then
          bridgeKeysOrNull
        else
          lib.subtractLists internalKeys (builtins.attrNames options);
    in
    {
      config = lib.genAttrs bridgeKeys (k: lib.mkIf (routed ? ${k}) routed.${k});
    };

  # flakeModule: can be used directly as a module or called with bridge keys.
  #   imports = [ inputs.den.flakeModule ];                  -- no bridging
  #   imports = [ (inputs.den.flakeModule ["flake-file"]) ]; -- with bridging
  flakeModuleOrBridge =
    args:
    if builtins.isList args then
      # Called with bridge keys: return a module that imports both
      # the base flake module and the bridge.
      {
        imports = [
          flakeModules.default
          (flakeBridge args)
        ];
      }
    else if args == true then
      # Called with `true`: auto-discover bridge keys from outer options.
      {
        imports = [
          flakeModules.default
          (flakeBridge null)
        ];
      }
    else
      # Called with module args by the module system: delegate to the base module.
      (import flakeModules.default) args;

in
{
  __functor = _: den-lib;
  lib = den-lib;
  namespace = import ./lib/namespace.nix;
  flakeOutputs = import ./flakeOutputs.nix;

  inherit nixModule templates flakeBridge;
  inherit (import ./flake-packages.nix) packages devShells;

  # flake-parts conventions
  flakeModule = flakeModuleOrBridge;
  inherit flakeModules;
  modules.flake = flakeModules;
}
