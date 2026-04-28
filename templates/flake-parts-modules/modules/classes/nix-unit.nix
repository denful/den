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
          fromClass = _: "tests";
          intoPath = _: [
            "nix-unit"
            "tests"
          ];
          # test helpers
          adaptArgs =
            args:
            let
              igloo = config.flake.nixosConfigurations.igloo.config;
              tux = igloo.users.users.tux;
            in
            args.config.allModuleArgs // { inherit igloo tux; };
        })
      ];
}
