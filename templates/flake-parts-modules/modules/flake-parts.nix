# Standard flake-parts wiring for den templates.
#
# Imports all third-party flake modules and wires collected
# class modules from den.policies.collect-perSystem into perSystem.
{
  inputs,
  den,
  config,
  lib,
  ...
}:
let
  # Evaluate class modules in a freeform submodule with perSystem args.
  # Used for `packages` which is lazyAttrsOf (not a submodule with imports).
  evalClassModules =
    specialArgs: modules:
    let
      result = lib.evalModules {
        inherit specialArgs;
        modules = [
          { _module.freeformType = lib.types.lazyAttrsOf lib.types.raw; }
        ]
        ++ modules;
      };
    in
    builtins.removeAttrs result.config [
      "_module"
      "warnings"
      "assertions"
    ];
in
{
  systems = builtins.attrNames den.hosts;

  imports = [
    inputs.den.flakeModule
    inputs.devshell.flakeModule
    inputs.treefmt-nix.flakeModule
    inputs.nix-unit.modules.flake.default
    inputs.files.flakeModules.default
    inputs.pkgs-by-name-for-flake-parts.flakeModule
  ];

  # Global nix-unit settings
  perSystem.nix-unit = {
    allowNetwork = true;
    inherit inputs;
  };

  # Wire collected class modules into perSystem.
  # config.flake.denModules.<system>.<class> holds raw module lists
  # produced by den.policies.collect-perSystem in den.nix.
  perSystem =
    { system, self', ... }@args:
    let
      dm = config.flake.denModules.${system} or { };
    in
    {
      treefmt.imports = dm.treefmt or [ ];

      devshells.default = {
        _module.args.self' = self';
        imports = dm.devshell or [ ];
      };

      packages = evalClassModules args (dm.packages or [ ]);

      nix-unit.tests = {
        _module.args = {
          tux = config.flake.nixosConfigurations.igloo.config.users.users.tux;
          igloo = config.flake.nixosConfigurations.igloo.config;
        };
        imports = dm.tests or [ ];
      };

      files.imports = dm.files or [ ];
    };
}
