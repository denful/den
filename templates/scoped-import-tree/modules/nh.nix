# Exposes flake apps under the name of each host / home for building with nh.
{
  den,
  lib,
  inputs,
  ...
}:
{

  flake.packages = lib.genAttrs lib.systems.flakeExposed (
    system:

    den.lib.nh.denPackages { fromFlake = true; } inputs.nixpkgs.legacyPackages.${system}
  );
}
