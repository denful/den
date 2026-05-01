{ den, inputs, ... }:
let
  inherit (den.lib.policy) route;
in
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  den.classes.treefmt = { };
  den.schema.flake-parts.policies.to-flake-parts-system-treefmt = _: [
    (route {
      fromClass = "treefmt";
      intoClass = "flake-parts";
      path = [ "treefmt" ];
      adaptArgs = { config, ... }: config.allModuleArgs;
    })
  ];
}
