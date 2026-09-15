{
  outputs =
    inputs:
    (inputs.nixpkgs.lib.evalModules {
      specialArgs = { inherit inputs; };
      modules = [ (inputs.import-tree ./modules) ];
    }).config.flake;

  inputs = {
    den.url = "github:denful/den";
    import-tree.url = "github:vic/import-tree";

    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    darwin.url = "github:nix-darwin/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    provider.url = "path:./provider";
    provider.inputs = {
      nixpkgs.follows = "nixpkgs";
      import-tree.follows = "import-tree";
      den.follows = "den";
    };

    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";

    nix-effects.url = "github:denful/nix-effects/den";
    nix-effects.inputs.nixpkgs.follows = "nixpkgs";
    nix-effects.inputs.nix-unit.follows = "nix-unit";

    # The gen HUB, not gen-schema directly: the hub binds every sibling's
    # `gen-*` input with `follows`, so one input yields one revision per
    # library. Pinning gen-schema here left its transitive closure to den and
    # produced three revisions of gen-prelude in this lock.
    gen.url = "github:sini/gen";
    gen.inputs.nixpkgs.follows = "nixpkgs";
  };
}
