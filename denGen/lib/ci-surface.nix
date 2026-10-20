# ciSurface: the den public surface Den's CI suite imports (design-ci-surface.md R1+R2).
denGen: {
  ciSurface =
    let
      nope = name: throw "denGen: ${name} not implemented";
      # Same output names Den's flakeOutputs declares; freeform leaves so many files may contribute.
      perSystem = [ "devShells" "packages" "apps" "checks" "tests" "legacyPackages" ];
      toplevel = [ "nixosConfigurations" "darwinConfigurations" "homeConfigurations" ];
      leaf = lib: lib.types.lazyAttrsOf lib.types.unspecified;
      out = ty: name: { lib, ... }: { options.flake.${name} = lib.mkOption { default = { }; type = ty lib; }; };
      flakeOutputs =
        builtins.listToAttrs (map (n: { name = n; value = out leaf n; }) toplevel)
        // builtins.listToAttrs (map (n: { name = n; value = out (lib: lib.types.lazyAttrsOf (leaf lib)) n; }) perSystem);

      # Fresh denGen eval per test; args mirror Den's denTest contract.
      denTest =
        inputs: extra: module:
        let
          lib = inputs.nixpkgs.lib;
          ev = lib.evalModules {
            specialArgs = { inherit lib inputs; };
            modules = [ module testModule helpers denGen.flakeModule extra ];
          };
          c = ev.config;
          hasExpected = !(c.expected ? undefined);
          expr = if hasExpected && builtins.isAttrs c.expected && builtins.isAttrs c.expr then builtins.intersectAttrs c.expected c.expr else c.expr;
        in
        { inherit expr; }
        // lib.optionalAttrs hasExpected { inherit (c) expected; }
        // lib.optionalAttrs (!(c.expectedError ? undefined)) { inherit (c) expectedError; };
      testModule = { lib, ... }: {
        options.expr = lib.mkOption { };
        options.expected = lib.mkOption { default.undefined = { }; };
        options.expectedError = lib.mkOption { default.undefined = { }; };
      };
      helpers = { config, ... }: let igloo = config.flake.nixosConfigurations.igloo.config; in {
        _module.args = {
          inherit igloo;
          iceberg = config.flake.nixosConfigurations.iceberg.config;
          apple = config.flake.darwinConfigurations.apple.config;
          tuxHm = igloo.home-manager.users.tux;
          pinguHm = igloo.home-manager.users.pingu;
          ns = nope "ns";
          trace = nope "trace";
          show = nope "show";
          funnyNames = nope "funnyNames";
        };
      };
    in
    {
      inherit flakeOutputs;
      denTestModule = { inputs, lib, config, ... }: {
        options.denTest = lib.mkOption { default = { }; type = lib.types.deferredModule; };
        config._module.args.denTest = denTest inputs config.denTest;
      };
    };
}
