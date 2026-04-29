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

  den.policies.flake-parts-to-flake-parts-system-tests =
    {
      __entityKind ? null,
      ...
    }:
    if __entityKind != "flake-parts" then
      [ ]
    else
      [
        (resolve.to "flake-parts-system" {
          fromClass = "tests";
          intoPath = [
            "nix-unit"
            "tests"
          ];
        })
      ];
}
