{
  den,
  ...
}:
let
  inherit (den.lib.policy) resolve;
in
{

  # A class for flake-parts' perSystem.packages
  # NOTE: this is different from Den's flake-packages class.
  den.classes.packages = { };
  den.policies.flake-parts-to-flake-parts-system-packages =
    {
      __entityKind ? null,
      ...
    }:
    if __entityKind != "flake-parts" then
      [ ]
    else
      [ (resolve.to "flake-parts-system" { fromClass = "packages"; }) ];
}
