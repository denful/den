{ den, inputs, ... }:
let
  inherit (den.lib.policy) resolve;
in
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  den.classes.treefmt = { };
  den.policies.flake-parts-to-flake-parts-system-treefmt =
    {
      __entityKind ? null,
      ...
    }:
    if __entityKind != "flake-parts" then
      [ ]
    else
      [ (resolve.to "flake-parts-system" { fromClass = _: "treefmt"; }) ];
}
