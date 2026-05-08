# Terranix integration: per-host Terraform config + plan/apply/destroy apps.
#
# Each host gets:
#   packages.<system>.<host>-tf     — config.tf.json derivation
#   apps.<system>.<host>-plan       — nix run .#<host>-plan
#   apps.<system>.<host>-apply      — nix run .#<host>-apply
#   apps.<system>.<host>-destroy    — nix run .#<host>-destroy
{
  inputs,
  den,
  lib,
  withSystem,
  ...
}:
let
  mkTfApp =
    host: system: cmd: config:
    withSystem system (
      { pkgs, ... }:
      {
        type = "app";
        program = toString (
          pkgs.writeShellScript "${host.name}-${cmd}" ''
            set -euo pipefail
            WORKDIR="''${TF_WORKDIR:-.terraform-${host.name}}"
            mkdir -p "$WORKDIR"
            cp ${config} "$WORKDIR/config.tf.json"
            cd "$WORKDIR"
            ${pkgs.opentofu}/bin/tofu init -input=false 2>/dev/null || ${pkgs.opentofu}/bin/tofu init
            ${pkgs.opentofu}/bin/tofu ${cmd}
          ''
        );
      }
    );

  # Single route that produces all per-host packages and apps at once.
  # Avoids multiple routes conflicting at the same flake output path.
  perSystemTerranix =
    { system, ... }:
    let
      hosts = builtins.attrValues (den.hosts.${system} or { });
    in
    lib.optionals (hosts != [ ]) [
      (den.lib.policy.route {
        fromClass = "terranix";
        intoClass = "flake";
        path = [
          "flake"
          "packages"
          system
        ];
        instantiate =
          { modules, ... }:
          lib.listToAttrs (
            map (
              host:
              lib.nameValuePair "${host.name}-tf" (
                inputs.terranix.lib.terranixConfiguration { inherit system modules; }
              )
            ) hosts
          );
      })
      (den.lib.policy.route {
        fromClass = "terranix";
        intoClass = "flake";
        path = [
          "flake"
          "apps"
          system
        ];
        instantiate =
          { modules, ... }:
          let
            mkHostApps =
              host:
              let
                config = inputs.terranix.lib.terranixConfiguration { inherit system modules; };
              in
              [
                (lib.nameValuePair "${host.name}-plan" (mkTfApp host system "plan" config))
                (lib.nameValuePair "${host.name}-apply" (mkTfApp host system "apply" config))
                (lib.nameValuePair "${host.name}-destroy" (mkTfApp host system "destroy" config))
              ];
          in
          lib.listToAttrs (lib.concatMap mkHostApps hosts);
      })
    ];
in
{
  den.policies.to-terranix = perSystemTerranix;
  den.schema.flake-system.includes = [ den.policies.to-terranix ];
}
