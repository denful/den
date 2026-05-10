{ den, inputs, ... }:
{
  imports = [ inputs.den.flakeModule ];

  #
  # There are two ways to run VMS:
  #
  # - NixOS configuration MicroVM runner as package.
  #   Den example: ./runnable-example.nix (by ./microvm-runners.nix)
  #   See https://microvm-nix.github.io/microvm.nix/packages.html
  #
  #
  # - MicroVM guests as part of a Host.
  #   Den example: ./guests-example.nix (by ./microvm-integration.nix)
  #   See https://microvm-nix.github.io/microvm.nix/host.html
  #       https://microvm-nix.github.io/microvm.nix/declarative.html
  #

  # automatically set hostname on all hosts.
  den.schema.host.includes = [ den.batteries.hostname ];
}
