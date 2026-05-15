{ den, inputs, ... }:
let
  inherit (den.lib.policy) route;
in
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  den.classes.treefmt = { };
  den.policies.treefmt-to-flake-parts = _: [
    (route {
      fromClass = "treefmt";
      intoClass = "flake-parts";
      path = [ "treefmt" ];
      adaptArgs = { config, ... }: config.allModuleArgs;
    })
  ];
  den.schema.flake-parts.includes = [ den.policies.treefmt-to-flake-parts ];
}
