# Tests for aspectContentType — the freeform wrapper that preserves
# multi-site definitions with file provenance and provider identity.
{
  denTest,
  inputs,
  lib,
  ...
}:
let
  # Minimal handler set for aspectToEffect tests.
  collectHandlers = {
    "emit-class" =
      { param, state }:
      {
        resume = null;
        state = state // {
          classes = (state.classes or [ ]) ++ [ param ];
        };
      };
    "emit-include" =
      { param, state }:
      {
        resume = [ (param.child or param) ];
        inherit state;
      };
    "register-constraint" =
      { param, state }:
      {
        resume = null;
        state = state // {
          constraints = (state.constraints or [ ]) ++ [ param ];
        };
      };
    "chain-push" =
      { param, state }:
      {
        resume = null;
        inherit state;
      };
    "chain-pop" =
      { param, state }:
      {
        resume = null;
        inherit state;
      };
    "resolve-complete" =
      { param, state }:
      {
        resume = param;
        inherit state;
      };
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
        comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
        result = den.lib.fx.handle {
          handlers = collectHandlers;
          state = { };
        } comp;
      in
      {
        expr = {
          classCount = builtins.length result.state.classes;
          className = (builtins.head result.state.classes).class;
          module = (builtins.head result.state.classes).module;
        };
        expected = {
          classCount = 1;
          className = "nixos";
          module = {
            enable = true;
          };
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
        comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
        result = den.lib.fx.handle {
          handlers = collectHandlers;
          state = { };
        } comp;
        # myTrait is unregistered — ignored by freeform-ignore
        emitted = builtins.filter (c: c.class == "myTrait") (result.state.classes or [ ]);
      in
      {
        expr = {
          emitCount = builtins.length emitted;
          resolvedOk = result.value.name == "dataTest";
        };
        expected = {
          emitCount = 0;
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
        comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
        result = den.lib.fx.handle {
          handlers = collectHandlers;
          state = { };
        } comp;
        emitted = builtins.filter (c: c.class == "myPackages") (result.state.classes or [ ]);
      in
      {
        expr = builtins.length emitted;
        expected = 0;
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
