{
  den,
  inputs,
  config,
  ...
}:
let
  inherit (den.lib.policy) resolve;
in
{
  imports = [ inputs.nix-unit.modules.flake.default ];
  den.classes.tests = { };

  # some globals
  perSystem.nix-unit = {
    allowNetwork = true;
    inputs = inputs;
  };

  den.schema.flake-parts.policies.to-flake-parts-system-tests = _: [
    (resolve.to "flake-parts-system" {
      fromClass = "tests";
      intoPath = [
        "nix-unit"
        "tests"
      ];
    })
  ];
}
