{
  outputs =
    inputs:
    (inputs.nixpkgs.lib.evalModules {
      modules = [ ./scoped.nix ];
      specialArgs = { inherit inputs; };
    }).config.flake;

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    import-tree.url = "github:vic/import-tree";
    ned.url = "github:denful/ned";
    pipe.url = "github:denful/pipe";
    bend.url = "github:denful/bend";
    den.url = "github:denful/den";
  };
}
