let
  sources = import ./npins;
  with-inputs = import sources.with-inputs sources {
    # uncomment for local checkout on CI
    # den.outPath = ./../..;
  };

  outputs =
    inputs:
    (inputs.nixpkgs.lib.evalModules {
      modules = [ (inputs.import-tree ./modules) ];
      specialArgs = {
        inherit inputs;
        inherit (inputs) self;
      };
    }).config;

in
with-inputs outputs
