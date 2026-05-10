# Terranix demo: two Hetzner hosts with Terraform infra generated from den aspects.
#
# Each host aspect contributes both NixOS config and Terraform resources.
# The terranix class collects all Terraform modules and produces config.tf.json.
#
# Usage:
#   nix build .#packages.x86_64-linux.tf    # generates config.tf.json
#   tofu init && tofu plan                   # run OpenTofu/Terraform
{
  lib,
  den,
  inputs,
  ...
}:
{
  den.classes.terranix = { };

  den.hosts.x86_64-linux = {
    web-1 = {
      server-type = "cx22";
      region = "fsn1";
      users.deploy = { };
    };
    web-2 = {
      server-type = "cx22";
      region = "nbg1";
      users.deploy = { };
    };
  };

  den.default = {
    nixos.system.stateVersion = "25.05";
    homeManager.home.stateVersion = "25.05";
  };

  den.default.includes = [
    den.batteries.define-user
    den.batteries.hostname
  ];

  den.systems = [ "x86_64-linux" ];
}
