# Tests for den's den.lib.fx.send "resolve" — the aspect compiler.
{
  denTest,
  inputs,
  lib,
  ...
}:
let
  # Test handler set that collects emitted effects.
  # emitIncludes now classifies children and sends typed effects
  # (check-dedup, resolve-aspect, etc.) instead of a single emit-include.
  # These mock handlers return children as-is without recursive resolution.
  mkCollectHandlers =
    den:
    let
      fx = den.lib.fx;
      handlers = den.lib.aspects.fx.handlers;
    in
    handlers.includeHandler
    // handlers.checkDedupHandler
    // handlers.constraintRegistryHandler
    // handlers.chainHandler
    // den.lib.aspects.fx.identity.pathSetHandler
    // den.lib.aspects.fx.identity.collectPathsHandler
    // handlers.resolveHandler
    // handlers.compileHandler
    // handlers.gateHandler
    // handlers.compileStaticHandler
    // handlers.compileParametricHandler
    // handlers.compileConditionalHandler
    // handlers.compileForwardHandler
    // handlers.bindHandler
    // handlers.deferHandler
    // handlers.drainHandler
    // handlers.classifyHandler
    // handlers.emitClassesHandler
    // handlers.resolveChildrenHandler
    // {
      "emit-class" =
        { param, state }:
        {
          resume = null;
          state = state // {
            classes = (state.classes or [ ]) ++ [ param ];
          };
        };
      "register-constraint" =
        { param, state }:
        {
          resume = null;
          state = state // {
            constraints = (state.constraints or [ ]) ++ [ param ];
          };
        };
      "resolve-complete" =
        { param, state }:
        {
          resume = param;
          inherit state;
        };
    }
    // fx.effects.state.handler;

  defaultState = {
    currentScope = "__test";
    scopedIncludesChain = _: { };
    scopedConstraintRegistry = _: { };
    scopedConstraintFilters = _: { };
    paths = [ ];
  };
in
{
  flake.tests.fx-aspect = {

    # Static aspect: emits emit-class for each class key.
    test-aspectToEffect-static = denTest (
      { den, ... }:
      let
        aspect = {
          name = "myAspect";
          meta = { };
          nixos = {
            enable = true;
          };
          includes = [ ];
        };
        comp = den.lib.fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
        result = den.lib.fx.handle {
          handlers = mkCollectHandlers den;
          state = defaultState;
        } comp;
      in
      {
        expr = {
          classCount = builtins.length result.state.classes;
          className = (builtins.head result.state.classes).class;
          module = (builtins.head result.state.classes).module;
          resolvedName = (builtins.head result.value).name;
        };
        expected = {
          classCount = 1;
          className = "nixos";
          module = {
            enable = true;
          };
          resolvedName = "myAspect";
        };
      }
    );

    # Static aspect with multiple classes.
    test-aspectToEffect-multi-class = denTest (
      { den, ... }:
      let
        aspect = {
          name = "multiClass";
          meta = { };
          nixos = {
            x = 1;
          };
          homeManager = {
            y = 2;
          };
          includes = [ ];
        };
        comp = den.lib.fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
        result = den.lib.fx.handle {
          handlers = mkCollectHandlers den;
          state = defaultState;
        } comp;
        classNames = map (c: c.class) result.state.classes;
      in
      {
        expr = builtins.sort builtins.lessThan classNames;
        expected = [
          "homeManager"
          "nixos"
        ];
      }
    );

    # Parametric aspect: bind.fn resolves named args via handlers.
    test-aspectToEffect-parametric = denTest (
      { den, ... }:
      let
        aspect = {
          name = "paramAspect";
          meta = { };
          __fn =
            { host }:
            {
              nixos = {
                hostName = host;
              };
              includes = [ ];
            };
          __args = {
            host = false;
          };
        };
        comp = den.lib.fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
        result = den.lib.fx.handle {
          handlers = mkCollectHandlers den // {
            host =
              { param, state }:
              {
                resume = "igloo";
                inherit state;
              };
          };
          state = defaultState;
        } comp;
      in
      {
        expr = {
          classCount = builtins.length result.state.classes;
          module = (builtins.head result.state.classes).module;
          resolvedName = (builtins.head result.value).name;
        };
        expected = {
          classCount = 1;
          module = {
            hostName = "igloo";
          };
          resolvedName = "paramAspect";
        };
      }
    );

    # Static aspect with class config: no functor needed in the den.lib.fx.pipeline.
    # Factory aspects (bare ctx arg) are not supported — use destructured args
    # or static attrsets.
    test-aspectToEffect-static-class = denTest (
      { den, ... }:
      let
        aspect = {
          name = "staticAspect";
          meta = { };
          nixos = {
            enabled = true;
          };
          includes = [ ];
        };
        comp = den.lib.fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
        result = den.lib.fx.handle {
          handlers = mkCollectHandlers den;
          state = defaultState;
        } comp;
      in
      {
        expr = {
          classCount = builtins.length result.state.classes;
          module = (builtins.head result.state.classes).module;
        };
        expected = {
          classCount = 1;
          module = {
            enabled = true;
          };
        };
      }
    );

    # Includes: emits emit-include for each child.
    test-aspectToEffect-includes = denTest (
      { den, ... }:
      let
        childA = {
          name = "childA";
          meta = { };
          includes = [ ];
        };
        childB = {
          name = "childB";
          meta = { };
          includes = [ ];
        };
        aspect = {
          name = "parent";
          meta = { };
          includes = [
            childA
            childB
          ];
        };
        comp = den.lib.fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
        result = den.lib.fx.handle {
          handlers = mkCollectHandlers den;
          state = defaultState;
        } comp;
      in
      {
        expr = {
          includeCount = builtins.length (builtins.head result.value).includes;
          firstChild = (builtins.head (builtins.head result.value).includes).name;
        };
        expected = {
          includeCount = 2;
          firstChild = "childA";
        };
      }
    );

    # Constraints: registers meta.handleWith entries.
    test-aspectToEffect-constraints = denTest (
      { den, ... }:
      let
        target = {
          name = "targetAspect";
          meta.provider = [ "pkg" ];
        };
        aspect = {
          name = "constrainedAspect";
          meta = {
            handleWith = [
              {
                type = "exclude";
                scope = "subtree";
                identity = "pkg/targetAspect";
              }
            ];
          };
          includes = [ ];
        };
        comp = den.lib.fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
        result = den.lib.fx.handle {
          handlers = mkCollectHandlers den;
          state = defaultState;
        } comp;
      in
      {
        expr = {
          constraintCount = builtins.length result.state.constraints;
          firstType = (builtins.head result.state.constraints).type;
          owner = (builtins.head result.state.constraints).owner;
        };
        expected = {
          constraintCount = 1;
          firstType = "exclude";
          owner = "constrainedAspect";
        };
      }
    );

  };
}
