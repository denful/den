# Tests for the unified emit-include handler with aspectToEffect.
{
  denTest,
  inputs,
  lib,
  ...
}:
let
  # Minimal handler set for testing aspectToEffect + includeHandler.
  mkTestHandlers =
    {
      den,
      extraHandlers ? { },
    }:
    let
      fx = den.lib.fx;
    in
    den.lib.aspects.fx.handlers.includeHandler
    // den.lib.aspects.fx.handlers.checkDedupHandler
    // den.lib.aspects.fx.handlers.resolveConditionalHandler
    // den.lib.aspects.fx.handlers.resolveParametricHandler
    // den.lib.aspects.fx.handlers.resolveAspectHandler
    // den.lib.aspects.fx.handlers.constraintRegistryHandler
    // {
      # Fallback probe-arg for custom handler sets without constantHandler.
      "probe-arg" =
        { param, state }:
        {
          resume =
            extraHandlers ? ${param}
            || builtins.elem param [
              "class"
              "aspect-chain"
            ];
          inherit state;
        };
    }
    // den.lib.aspects.fx.handlers.chainHandler
    // den.lib.aspects.fx.identity.pathSetHandler
    // den.lib.aspects.fx.identity.collectPathsHandler
    // {
      "emit-class" =
        { param, state }:
        {
          resume = null;
          state = state // {
            classes = (state.classes or [ ]) ++ [ param ];
          };
        };
      "resolve-complete" =
        { param, state }:
        {
          resume = param;
          state = state // {
            names = (state.names or [ ]) ++ [ (param.name or "<anon>") ];
          };
        };
      "check-constraint" =
        { param, state }:
        {
          resume = {
            action = "keep";
          };
          inherit state;
        };
    }
    // extraHandlers
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
  flake.tests.fx-effectful-resolve = {

    # Basic: parent with child, both resolved via aspectToEffect.
    test-basic-aspectToEffect = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        parent = {
          name = "parent";
          meta = { };
          nixos = {
            a = 1;
          };
          includes = [
            {
              name = "child";
              meta = { };
              nixos = {
                b = 2;
              };
              includes = [ ];
            }
          ];
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect parent;
        result = fx.handle {
          handlers = mkTestHandlers { inherit den; };
          state = defaultState;
        } comp;
      in
      {
        expr = {
          parentName = result.value.name;
          childName = (builtins.head result.value.includes).name;
          classCount = builtins.length result.state.classes;
          resolvedNames = result.state.names;
        };
        expected = {
          parentName = "parent";
          childName = "child";
          classCount = 2;
          resolvedNames = [
            "child"
            "parent"
          ];
        };
      }
    );

    # Constraint: exclude a child via handleWith.
    test-exclude-child = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        parent = {
          name = "parent";
          meta = {
            handleWith = [
              {
                type = "exclude";
                scope = "subtree";
                identity = "drop";
              }
            ];
          };
          includes = [
            {
              name = "keep";
              meta = { };
              nixos = {
                a = 1;
              };
              includes = [ ];
            }
            {
              name = "drop";
              meta = { };
              nixos = {
                b = 2;
              };
              includes = [ ];
            }
          ];
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect parent;
        result = fx.handle {
          handlers = mkTestHandlers { inherit den; } // den.lib.aspects.fx.handlers.constraintRegistryHandler;
          state = defaultState;
        } comp;
        children = result.value.includes;
      in
      {
        expr = {
          count = builtins.length children;
          firstName = (builtins.elemAt children 0).name;
          secondExcluded = (builtins.elemAt children 1).meta.excluded;
        };
        expected = {
          count = 2;
          firstName = "keep";
          secondExcluded = true;
        };
      }
    );

    # Parametric child resolved through handler-provided args.
    test-parametric-child = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        parent = {
          name = "root";
          meta = { };
          includes = [
            {
              name = "web";
              meta = { };
              __fn =
                { host }:
                {
                  nixos.hostName = host;
                  includes = [ ];
                };
              __args = {
                host = false;
              };
            }
          ];
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect parent;
        hostHandler = {
          host =
            { param, state }:
            {
              resume = "igloo";
              inherit state;
            };
        };
        result = fx.handle {
          handlers = mkTestHandlers {
            inherit den;
            extraHandlers = hostHandler;
          };
          state = defaultState;
        } comp;
        child = builtins.head result.value.includes;
      in
      {
        expr = child.nixos.hostName;
        expected = "igloo";
      }
    );

    # resolve-complete fires for each node.
    test-resolve-complete-collects = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        parent = {
          name = "root";
          meta = { };
          includes = [
            {
              name = "a";
              meta = { };
              includes = [ ];
            }
            {
              name = "b";
              meta = { };
              includes = [ ];
            }
          ];
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect parent;
        result = fx.handle {
          handlers = mkTestHandlers { inherit den; };
          state = defaultState;
        } comp;
      in
      {
        expr = result.state.names;
        expected = [
          "a"
          "b"
          "root"
        ];
      }
    );

    # Nested excludes: inner excludes B, outer excludes A.
    test-nested-excludes = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        parent = {
          name = "root";
          meta = {
            handleWith = [
              {
                type = "exclude";
                scope = "subtree";
                identity = "A";
              }
            ];
          };
          includes = [
            {
              name = "inner";
              meta = {
                handleWith = [
                  {
                    type = "exclude";
                    scope = "subtree";
                    identity = "B";
                  }
                ];
              };
              includes = [
                {
                  name = "B";
                  meta = { };
                  nixos = {
                    b = 1;
                  };
                  includes = [ ];
                }
              ];
            }
            {
              name = "A";
              meta = { };
              nixos = {
                a = 1;
              };
              includes = [ ];
            }
          ];
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect parent;
        result = fx.handle {
          handlers = mkTestHandlers { inherit den; } // den.lib.aspects.fx.handlers.constraintRegistryHandler;
          state = defaultState;
        } comp;
        excludedNames = builtins.filter (n: lib.hasPrefix "~" n) result.state.names;
      in
      {
        expr = builtins.sort builtins.lessThan excludedNames;
        expected = [
          "~A"
          "~B"
        ];
      }
    );

    # Bare function include gets wrapped and resolved.
    test-bare-function-include = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        parent = {
          name = "root";
          meta = { };
          includes = [
            (
              { host }:
              {
                nixos.hostName = host;
              }
            )
          ];
        };
        hostHandler = {
          host =
            { param, state }:
            {
              resume = "igloo";
              inherit state;
            };
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect parent;
        result = fx.handle {
          handlers = mkTestHandlers {
            inherit den;
            extraHandlers = hostHandler;
          };
          state = defaultState;
        } comp;
        child = builtins.head result.value.includes;
      in
      {
        expr = child.nixos.hostName;
        expected = "igloo";
      }
    );

  };
}
