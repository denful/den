# This repo was generated with github:vic/flake-file#dendritic template.
# Run `nix run .#write-flake` after changing any input.
#
# Inputs can be placed in any module, the best practice is to have them
# as close as possible to their actual usage.
# See: https://dendritic.oeiuwq.com/Dendritic.html#minimal-and-focused-flakenix
#
# For our template, we enable home-manager and nix-darwin by default, but
# you are free to remove them if not being used by you.
{

  flake-file.inputs = {
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ## these stable inputs are for wsl
    #nixpkgs-stable.url = "github:nixos/nixpkgs/release-25.05";
    #home-manager-stable.url = "github:nix-community/home-manager/release-25.05";
    #home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";

    #nixos-wsl = {
    #  url = "github:nix-community/nixos-wsl";
    #  inputs.nixpkgs.follows = "nixpkgs-stable";
    #  inputs.flake-compat.follows = "";
    #};

  };

}
