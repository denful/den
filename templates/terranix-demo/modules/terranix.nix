# Terranix integration: feed den's terranix class modules into terranix's flake-module.
#
# terranix's flake-module handles all output generation:
#   nix run .#<host>           — tofu apply
#   nix run .#<host>.plan      — tofu plan
#   nix run .#<host>.destroy   — tofu destroy
#   nix develop .#<host>       — shell with tofu + scripts
{
  inputs,
  den,
  lib,
  ...
}:
let
  inherit (den.lib.aspects) resolveImports;
  inherit (den.lib) resolveEntity;
  terranixModules = (resolveImports "terranix" (resolveEntity "flake" { })).imports;
in
{
  imports = [ inputs.terranix.flakeModule ];

  perSystem =
    { pkgs, system, ... }:
    {
      terranix.terranixConfigurations = lib.mapAttrs (_: host: {
        modules = terranixModules;
        terraformWrapper.package = pkgs.opentofu;
      }) (den.hosts.${system} or { });
    };
}
