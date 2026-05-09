{
  den,
  ...
}:
let
  inherit (den.lib.policy) route;
in
{

  # A class for flake-parts' perSystem.packages
  # NOTE: this is different from Den's flake-packages class.
  den.classes.packages = { };
  den.policies.to-flake-parts-system-packages = _: [
    (route {
      fromClass = "packages";
      intoClass = "flake-parts";
      collectSubtree = true;
      path = [ "packages" ];
      adaptArgs = { config, ... }: config.allModuleArgs;
    })
  ];
  den.schema.flake-parts.includes = [ den.policies.to-flake-parts-system-packages ];
}
