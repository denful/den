# Flake-parts entity policies — users include these explicitly via den.schema.
{
  den,
  lib,
  inputs,
  ...
}:
lib.mkIf (inputs ? flake-parts) {
  den.policies.to-flake-parts =
    { system, ... }:
    [
      (den.lib.policy.resolve.to "flake-parts" {
        flake-parts = {
          name = "flake-parts-${system}";
          aspect = { };
        };
      })
    ];

  den.policies.to-flake-parts-packages = _: [
    (den.lib.policy.route {
      fromClass = "packages";
      intoClass = "flake-parts";
      collectSubtree = true;
      path = [ "packages" ];
      adaptArgs = { config, ... }: config.allModuleArgs;
    })
  ];

  den.schema.flake-parts.isEntity = true;
}
