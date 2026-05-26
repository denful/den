# Test helpers for evaluating Den on isolation
#
# Exports _module.args.denTest
{
  inputs,
  lib,
  config,
  ...
}:
let
  # isolated test, prevent polution between tests.
  denTest =
    module:
    let
      config = (evalDen module).config;
      expected = config.expected;
      hasExpected = !(expected ? undefined);
      # Partial matching: when both expr and expected are attrsets,
      # only compare the keys present in expected.
      expr =
        if hasExpected && builtins.isAttrs expected && builtins.isAttrs config.expr then
          builtins.intersectAttrs expected config.expr
        else
          config.expr;
    in
    {
      inherit expr;
    }
    // lib.optionalAttrs hasExpected {
      inherit expected;
    }
    // lib.optionalAttrs (!(config.expectedError ? undefined)) {
      expectedError = config.expectedError;
    };

  # emulate fake-parts only for self and nixpkgs.
  withSystem =
    system:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      inputs'.nixpkgs.packages = pkgs;
      inputs'.nixpkgs.legacyPackages = pkgs;
      self'.packages = pkgs;
      self'.legacyPackages = pkgs;
    in
    cb: cb { inherit inputs' self'; };

  evalDen =
    module:
    lib.evalModules {
      specialArgs = {
        inherit inputs;
        inherit withSystem;
      };
      modules = [
        module
        testModule
        helpersModule
        config.denTest
      ];
    };

  testModule = {
    imports = [ inputs.den.flakeModule ];
    options.expr = lib.mkOption { };
    options.expected = lib.mkOption { default.undefined = { }; };
    options.expectedError =
      let
        # lib.types.submodule doesn't work well in types.either or types.oneOf because it lazily evaluates keys
        # so we need to strictly check the keys with an additional check
        strictSubmodule = module: lib.types.addCheck (lib.types.submodule module) (strictKeys module);

        strictKeys =
          module: attrs:
          lib.pipe module [
            (x: x.options)
            (lib.attrNames)
            (lib.lists.all (key: attrs ? ${key}))
          ];

        type = lib.mkOption {
          type = lib.types.enum [
            "RestrictedPathError"
            "MissingArgumentError"
            "UndefinedVarError"
            "TypeError"
            "Abort"
            "ThrownError"
            "AssertionError"
            "ParseError"
            "EvalError"
          ];
        };

        msg = lib.mkOption { type = lib.types.str; };

        undefined = lib.mkOption { default.undefined = { }; };

      in
      lib.mkOption {
        type = lib.types.oneOf [
          (strictSubmodule { options = { inherit undefined; }; })
          (strictSubmodule { options = { inherit type msg; }; })
        ];
        default.undefined = { };
      };
    config = {
      den.schema.user.classes = lib.mkDefault [ "homeManager" ];
      den.default.nixos.system.stateVersion = lib.mkDefault "25.11";
      den.default.homeManager.home.stateVersion = lib.mkDefault "25.11";
    };
  };

  helpersModule =
    { config, den, ... }:
    let

      iceberg = config.flake.nixosConfigurations.iceberg.config;
      apple = config.flake.darwinConfigurations.apple.config;
      igloo = config.flake.nixosConfigurations.igloo.config;
      tuxHm = igloo.home-manager.users.tux;
      pinguHm = igloo.home-manager.users.pingu;

      sort = lib.sort (a: b: a < b);
      show = items: builtins.trace (lib.concatStringsSep " / " (lib.flatten [ items ]));

      # Trace utility: resolve an aspect tree and return { trace, imports }.
      # trace is the legacy-compatible tree shape: ["name" ["child" ...] ...]
      trace =
        class: aspect:
        let
          fxTrace = den.lib.aspects.fx.trace;
          pipeline = den.lib.aspects.fx.pipeline;
          result =
            pipeline.mkPipeline
              {
                inherit class;
                extraHandlers = fxTrace.tracingHandler class;
                extraState = {
                  entries = [ ];
                };
              }
              {
                self = aspect;
                ctx = { };
              };
          entries = result.state.entries or [ ];
          # Build legacy tree shape from flat entries
          buildTree =
            parentName: entries:
            let
              children = builtins.filter (e: e.parent == parentName) entries;
              mkNode =
                e:
                let
                  displayName = if e.excluded then "~${e.name}" else e.name;
                  subs = buildTree (
                    if e.isProvider then "${lib.concatStringsSep "/" e.provider}/${e.name}" else e.name
                  ) entries;
                in
                if subs == [ ] then [ displayName ] else [ displayName ] ++ subs;
            in
            builtins.concatLists (map (e: [ (mkNode e) ]) children);
          roots = builtins.filter (e: e.parent == null) entries;
          traceTree =
            if roots == [ ] then
              [ ]
            else
              let
                root = builtins.head roots;
                rootName =
                  if root.isProvider then "${lib.concatStringsSep "/" root.provider}/${root.name}" else root.name;
              in
              [ root.name ] ++ buildTree rootName entries;
        in
        {
          imports =
            let
              scoped = result.state.scopedClassImports null;
              flat = builtins.foldl' (
                acc: sd:
                lib.zipAttrsWith (_: builtins.concatLists) [
                  acc
                  sd
                ]
              ) { } (builtins.attrValues scoped);
            in
            flat.${class} or [ ];
          trace = traceTree;
        };

      funnyNames =
        aspect:
        let
          resolve = config.den.lib.aspects.resolve;
          mod = resolve "funny" aspect;
          namesMod = {
            options.names = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
          };
          res = lib.evalModules {
            modules = [
              mod
              namesMod
            ];
          };
        in
        sort res.config.names;

    in
    {
      _module.args = {
        inherit
          show
          funnyNames
          apple
          igloo
          iceberg
          tuxHm
          pinguHm
          trace
          ;
      };
    };
in
{
  config._module.args = { inherit denTest; };
  options.denTest = lib.mkOption {
    default = { };
    type = lib.types.deferredModule;
  };
}
