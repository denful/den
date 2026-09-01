let
  sources = import ./npins;
  with-inputs = import sources.with-inputs sources {
    # Uncomment for local checkout on CI.
    # Do NOT commit this line uncommented, or it will break the template for new users.
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
