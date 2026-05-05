# Tests for aspectContentType — the freeform wrapper that preserves
# multi-site definitions with file provenance and provider identity.
{
  denTest,
  inputs,
  lib,
  ...
}:
let
  # Run fx.send "resolve" through the pipeline with an emit-class capture overlay.
  resolveWithCapture =
    den: aspect:
    let
      pipeline = den.lib.aspects.fx.pipeline;
      captureHandler = {
        "emit-class" =
          { param, state }:
          {
            resume = null;
            state = state // {
              classes = (state.classes or [ ]) ++ [ param ];
            };
          };
      };
      result = pipeline.fxFullResolve {
        class = "nixos";
        self = aspect;
        ctx = { };
        extraState = {
          classes = [ ];
        };
      };
    in
    result
    // {
      # Extract classes from scopedClassImports (flat merge across scopes).
      classes =
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
        flat;
    };
in
{
  flake.tests.aspect-content-type = {

    # Class keys still work through the pipeline — emitClasses unwraps
    # __contentValues and passes the module value to wrapClassModule.
    test-class-key-unwrap = denTest (
      { den, ... }:
      let
        aspect = {
          name = "classTest";
          meta = { };
          nixos = {
            enable = true;
          };
          includes = [ ];
        };
        result = resolveWithCapture den aspect;
        nixosImports = result.classes.nixos or [ ];
      in
      {
        expr = {
          hasNixos = nixosImports != [ ];
        };
        expected = {
          hasNixos = true;
        };
      }
    );

    # Unregistered attrset keys are ignored (not emitted as classes).
    test-plain-data-attrset = denTest (
      { den, ... }:
      let
        aspect = {
          name = "dataTest";
          meta = { };
          myTrait = {
            foo = "bar";
            baz = 42;
          };
          includes = [ ];
        };
        result = resolveWithCapture den aspect;
        resolvedValue = builtins.head result.value;
      in
      {
        expr = {
          hasMyTrait = (result.classes.myTrait or [ ]) != [ ];
          resolvedOk = resolvedValue.name == "dataTest";
        };
        expected = {
          hasMyTrait = true;
          resolvedOk = true;
        };
      }
    );

    # Unregistered list keys are ignored (not emitted as classes).
    test-plain-data-list = denTest (
      { den, ... }:
      let
        aspect = {
          name = "listTest";
          meta = { };
          myPackages = [
            "vim"
            "git"
          ];
          includes = [ ];
        };
        result = resolveWithCapture den aspect;
        # myPackages is unregistered — emitted as class.
        # List values produce class entries.
        myPkgImports = result.classes.myPackages or [ ];
      in
      {
        expr = builtins.length myPkgImports;
        expected = 2;
      }
    );

    # aspectContentType wraps values with __contentValues and __provider.
    test-content-wrapper-shape = denTest (
      { den, ... }:
      let
        contentType = (den.lib.aspects.mkAspectsType { providerPrefix = [ "test" ]; }).aspectContentType;
        evaluated = lib.evalModules {
          modules = [
            { freeformType = lib.types.lazyAttrsOf contentType; }
            { myKey = "hello"; }
          ];
        };
        val = evaluated.config.myKey;
      in
      {
        expr = {
          hasContentValues = val ? __contentValues;
          hasProvider = val ? __provider;
          provider = val.__provider;
          valueCount = builtins.length val.__contentValues;
        };
        expected = {
          hasContentValues = true;
          hasProvider = true;
          provider = [
            "test"
            "myKey"
          ];
          valueCount = 1;
        };
      }
    );

    # Multi-site definitions preserve all defs with file provenance.
    test-multi-site-merge = denTest (
      { den, ... }:
      let
        contentType = (den.lib.aspects.mkAspectsType { providerPrefix = [ ]; }).aspectContentType;
        evaluated = lib.evalModules {
          modules = [
            { freeformType = lib.types.lazyAttrsOf contentType; }
            { myKey = "first"; }
            { myKey = "second"; }
          ];
        };
        val = evaluated.config.myKey;
      in
      {
        expr = {
          valueCount = builtins.length val.__contentValues;
          values = builtins.sort builtins.lessThan (map (d: d.value) val.__contentValues);
        };
        expected = {
          valueCount = 2;
          values = [
            "first"
            "second"
          ];
        };
      }
    );

    # Function values accepted (trait emissions can be functions).
    test-function-value = denTest (
      { den, ... }:
      let
        contentType = (den.lib.aspects.mkAspectsType { providerPrefix = [ ]; }).aspectContentType;
        evaluated = lib.evalModules {
          modules = [
            { freeformType = lib.types.lazyAttrsOf contentType; }
            { myFn = x: x + 1; }
          ];
        };
        val = evaluated.config.myFn;
        extractedFn = (builtins.head val.__contentValues).value;
      in
      {
        expr = extractedFn 5;
        expected = 6;
      }
    );

  };
}
