{
  den,
  inputs,
  config,
  ...
}:
let
  inherit (den.lib.policy) route;
in
{
  imports = [ inputs.nix-unit.modules.flake.default ];
  den.classes.tests = { };

  # some globals
  perSystem.nix-unit = {
    allowNetwork = true;
    inputs = inputs;
  };

  den.policies.to-flake-parts-system-tests = _: [
    (route {
      fromClass = "tests";
      intoClass = "flake-parts";
      path = [
        "nix-unit"
        "tests"
      ];
      adaptArgs = { config, ... }: config.allModuleArgs;
    })
  ];
  den.schema.flake-parts.includes = [ den.policies.to-flake-parts-system-tests ];
}
