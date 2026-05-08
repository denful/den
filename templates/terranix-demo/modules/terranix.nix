# Terranix integration: policy.instantiate collects modules, terranix flake-module
# provides apps (plan/apply/destroy), devShells, and packages.
#
#   nix run .#<host>           — tofu apply
#   nix run .#<host>.plan      — tofu plan
#   nix run .#<host>.destroy   — tofu destroy
#   nix develop .#<host>       — shell with tofu + scripts
#   nix build .#<host>.config  — config.tf.json
{
  den,
  inputs,
  lib,
  config,
  ...
}:
{
  imports = [ inputs.terranix.flakeModule ];

  den.classes.terranix = { };

  # Per-host: collect terranix class modules from host subtree,
  # store the raw module list at terranixModules.<host>.
  den.policies.host-to-terranix =
    { host, ... }:
    [
      (den.lib.policy.instantiate {
        name = "${host.name}-tf";
        class = "terranix";
        instantiate = { modules, ... }: modules;
        intoAttr = [
          "terranixModules"
          host.name
        ];
      })
    ];

  den.schema.host.includes = [ den.policies.host-to-terranix ];

  # Feed pipeline-collected modules into terranix's flake-module.
  perSystem =
    { pkgs, system, ... }:
    {
      terranix.terranixConfigurations = lib.mapAttrs (_: modules: {
        inherit modules;
        terraformWrapper.package = pkgs.opentofu;
      }) (config.flake.terranixModules or { });
    };
}
