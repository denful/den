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
          # Den denTest.nix:37-46 fake-parts withSystem: only self and nixpkgs.
          withSystem = system: let pkgs = inputs.nixpkgs.legacyPackages.${system}; in cb: cb {
            inputs'.nixpkgs = { packages = pkgs; legacyPackages = pkgs; };
            self' = { packages = pkgs; legacyPackages = pkgs; };
          };
          ev = lib.evalModules {
            specialArgs = { inherit lib inputs withSystem; };
            modules = [ module testModule fixture helpers denGen.flakeModule extra ];
          };
          c = ev.config;
          hasExpected = !(c.expected ? undefined);
          expr = if hasExpected && builtins.isAttrs c.expected && builtins.isAttrs c.expr then builtins.intersectAttrs c.expected c.expr else c.expr;
        in
        { inherit expr; }
        // lib.optionalAttrs hasExpected { inherit (c) expected; }
        // lib.optionalAttrs (!(c.expectedError ? undefined)) { inherit (c) expectedError; };
      # Den denTest.nix:108-110 pre-declares these for every eval.
      fixture = { lib, ... }: {
        den.schema.user.classes = lib.mkDefault [ "homeManager" ];
        den.default.nixos.system.stateVersion = lib.mkDefault "25.11";
        den.default.homeManager.home.stateVersion = lib.mkDefault "25.11";
      };
      testModule = { lib, ... }: {
        options.expr = lib.mkOption { };
        options.expected = lib.mkOption { default.undefined = { }; };
        options.expectedError = lib.mkOption { default.undefined = { }; };
      };
      helpers = { lib, config, ... }: let igloo = config.flake.nixosConfigurations.igloo.config; in {
        _module.args = {
          inherit igloo;
          iceberg = config.flake.nixosConfigurations.iceberg.config;
          apple = config.flake.darwinConfigurations.apple.config;
          tuxHm = igloo.home-manager.users.tux;
          pinguHm = igloo.home-manager.users.pingu;
          trace = nope "trace";
          show = nope "show";
          funnyNames = aspect:
            let
              den = config._module.args.den;
              mods = lib.concatMap (a: lib.optional (a.content ? funny) (denGen.content.classModule { } a.content.funny)) (denGen.closure den.aspects aspect);
              names = lib.evalModules { modules = mods ++ [ { options.names = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; }; } ]; };
            in
            lib.sort (a: b: a < b) names.config.names;
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
