{
  inputs.gen.url = "github:sini/gen/bcbc5ca579614643fa3433034fd0248b0d551f65";
  inputs.gen.inputs.nixpkgs.follows = "";
  outputs = inputs: let denGen = import ./default.nix { gen = import inputs.gen.outPath { }; }; in {
    lib = denGen;
    flakeModule = denGen.flakeModule;
    flakeModules.default = denGen.flakeModule;   # flake-parts variant comes later
    templates.minimal = { path = ./templates/minimal; description = "denGen minimal"; };
  };
}
