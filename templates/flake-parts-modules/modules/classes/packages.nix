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
  den.schema.flake-parts.policies.to-flake-parts-system-packages = _: [
    (resolve.to "flake-parts-system" { fromClass = "packages"; })
  ];
}
