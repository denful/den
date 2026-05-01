{ den, inputs, ... }:
let
  inherit (den.lib.policy) resolve;
in
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  den.classes.treefmt = { };
  den.schema.flake-parts.policies.to-flake-parts-system-treefmt = _: [
    (resolve.to "flake-parts-system" { fromClass = "treefmt"; })
  ];
}
