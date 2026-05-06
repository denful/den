{ den, inputs, ... }:
let
  inherit (den.lib.policy) route;
in
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  den.classes.treefmt = { };
  den.policies.to-flake-parts-system-treefmt = _: [
    (route {
      fromClass = "treefmt";
      intoClass = "flake-parts";
      path = [ "treefmt" ];
      adaptArgs = { config, ... }: config.allModuleArgs;
    })
  ];
  den.schema.flake-parts.includes = [ den.policies.to-flake-parts-system-treefmt ];
}
