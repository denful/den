{
  denTest,
  lib,
  ...
}:
{
  flake.tests.fx-compile-static = {

    # Minimal static aspect (no class handler, no nested keys) →
    # gate passes, classify returns empty, resolve-children is called.
    test-static-minimal = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        identity = den.lib.aspects.fx.identity;
        aspect = {
          name = "simple-aspect";
          meta = { };
        };
        param = {
          inherit aspect;
          identity = "simple-aspect";
          ctx = { };
        };
        state = den.lib.aspects.fx.pipeline.defaultState;
        stubs = {
          "check-dedup" =
            { param, state }:
            {
              resume = {
                isDuplicate = false;
                dedupKey = null;
              };
              inherit state;
            };
          "check-constraint" =
            { param, state }:
            {
              resume = {
                action = "allow";
              };
              inherit state;
            };
          "resolve-complete" =
            { param, state }:
            {
              resume = param;
              inherit state;
            };
          "classify" =
            { param, state }:
            {
              resume = {
                classKeys = [ ];
                nestedKeys = [ ];
              };
              inherit state;
            };
          "emit-classes" =
            { param, state }:
            {
              resume = [ ];
              inherit state;
            };
          "register-constraint" =
            { param, state }:
            {
              resume = null;
              inherit state;
            };
          "resolve-children" =
            { param, state }:
            {
              resume = fx.pure (param.aspect // { includes = [ ]; });
              inherit state;
            };
        };
        comp = fx.send "compile-static" param;
        result = fx.handle {
          handlers =
            handlers.compileStaticHandler // handlers.gateHandler // identity.collectPathsHandler // stubs;
          inherit state;
        } comp;
        resolved = builtins.head result.value;
      in
      {
        expr = resolved.name;
        expected = "simple-aspect";
      }
    );

    # Gate blocks (dedup): resumes gate result directly.
    test-gate-blocks = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        aspect = {
          name = "dup-aspect";
        };
        param = {
          inherit aspect;
          identity = "dup-aspect";
          ctx = { };
        };
        state = den.lib.aspects.fx.pipeline.defaultState;
        stubs = {
          "gate" =
            { param, state }:
            {
              resume = fx.pure {
                blocked = true;
                result = [ ];
              };
              inherit state;
            };
        };
        comp = fx.send "compile-static" param;
        result = fx.handle {
          handlers = handlers.compileStaticHandler // stubs;
          inherit state;
        } comp;
      in
      {
        expr = result.value;
        expected = [ ];
      }
    );

    # Gate passes with constraint owner: tags aspect meta.
    test-constraint-owner-tagging = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        identity = den.lib.aspects.fx.identity;
        aspect = {
          name = "owned-aspect";
          meta = { };
        };
        param = {
          inherit aspect;
          identity = "owned-aspect";
          ctx = { };
        };
        state = den.lib.aspects.fx.pipeline.defaultState;
        stubs = {
          "gate" =
            { param, state }:
            {
              resume = fx.pure {
                passed = true;
                owner = "constraint-abc";
              };
              inherit state;
            };
          # Capture the aspect that classify receives to verify tagging.
          "classify" =
            { param, state }:
            {
              resume = {
                classKeys = [ ];
                nestedKeys = [ ];
              };
              inherit state;
            };
          "emit-classes" =
            { param, state }:
            {
              resume = [ ];
              inherit state;
            };
          "register-constraint" =
            { param, state }:
            {
              resume = null;
              inherit state;
            };
          # Capture the aspect in resolve-children to check constraintOwner.
          "resolve-children" =
            { param, state }:
            {
              resume = fx.pure param.aspect;
              inherit state;
            };
        };
        comp = fx.send "compile-static" param;
        result = fx.handle {
          handlers = handlers.compileStaticHandler // stubs;
          inherit state;
        } comp;
        resolved = builtins.head result.value;
      in
      {
        expr = resolved.meta.constraintOwner or null;
        expected = "constraint-abc";
      }
    );

    # Static with class keys: classify + emit-classes are called.
    test-static-with-class-keys = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        identity = den.lib.aspects.fx.identity;
        aspect = {
          name = "class-aspect";
          meta = { };
          users = { };
        };
        param = {
          inherit aspect;
          identity = "class-aspect";
          ctx = { };
        };
        state = den.lib.aspects.fx.pipeline.defaultState;
        emitClassesCalled = builtins.unsafeGetAttrPos "name" { name = true; };
        stubs = {
          "check-dedup" =
            { param, state }:
            {
              resume = {
                isDuplicate = false;
                dedupKey = null;
              };
              inherit state;
            };
          "check-constraint" =
            { param, state }:
            {
              resume = {
                action = "allow";
              };
              inherit state;
            };
          "resolve-complete" =
            { param, state }:
            {
              resume = param;
              inherit state;
            };
          "classify" =
            { param, state }:
            {
              resume = {
                classKeys = [ "users" ];
                nestedKeys = [ ];
              };
              inherit state;
            };
          # Track that emit-classes was called with the right classKeys.
          "emit-classes" =
            { param, state }:
            {
              resume = param.classKeys;
              inherit state;
            };
          "register-constraint" =
            { param, state }:
            {
              resume = null;
              inherit state;
            };
          "resolve-children" =
            { param, state }:
            {
              resume = fx.pure (param.aspect // { __emitClassesCalled = true; });
              inherit state;
            };
        };
        comp = fx.send "compile-static" param;
        result = fx.handle {
          handlers =
            handlers.compileStaticHandler // handlers.gateHandler // identity.collectPathsHandler // stubs;
          inherit state;
        } comp;
        resolved = builtins.head result.value;
      in
      {
        expr = resolved.__emitClassesCalled or false;
        expected = true;
      }
    );

    # Static with nested keys: resolve is called for each nested key.
    test-static-with-nested-keys = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        identity = den.lib.aspects.fx.identity;
        aspect = {
          name = "parent-aspect";
          meta = { };
          nested-child = {
            name = "nested-child";
          };
        };
        param = {
          inherit aspect;
          identity = "parent-aspect";
          ctx = { };
        };
        state = den.lib.aspects.fx.pipeline.defaultState;
        stubs = {
          "check-dedup" =
            { param, state }:
            {
              resume = {
                isDuplicate = false;
                dedupKey = null;
              };
              inherit state;
            };
          "check-constraint" =
            { param, state }:
            {
              resume = {
                action = "allow";
              };
              inherit state;
            };
          "resolve-complete" =
            { param, state }:
            {
              resume = param;
              inherit state;
            };
          "classify" =
            { param, state }:
            {
              resume = {
                classKeys = [ ];
                nestedKeys = [ "nested-child" ];
              };
              inherit state;
            };
          "emit-classes" =
            { param, state }:
            {
              resume = [ ];
              inherit state;
            };
          "register-constraint" =
            { param, state }:
            {
              resume = null;
              inherit state;
            };
          # Stub resolve to capture nested aspect.
          "resolve" =
            { param, state }:
            {
              resume = [ param.aspect ];
              inherit state;
            };
          "resolve-children" =
            { param, state }:
            {
              resume = fx.pure (param.aspect // { includes = [ ]; });
              inherit state;
            };
        };
        comp = fx.send "compile-static" param;
        result = fx.handle {
          handlers =
            handlers.compileStaticHandler // handlers.gateHandler // identity.collectPathsHandler // stubs;
          inherit state;
        } comp;
        resolved = builtins.head result.value;
      in
      {
        expr = resolved.name;
        expected = "parent-aspect";
      }
    );

    # Parametric internal keys are stripped before processing.
    test-strips-parametric-keys = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        identity = den.lib.aspects.fx.identity;
        aspect = {
          name = "strip-aspect";
          meta = { };
          __fn = _: { };
          __args = {
            host = false;
          };
          __parametricDepth = 2;
          __parametricResolvedArgs = [ "host" ];
        };
        param = {
          inherit aspect;
          identity = "strip-aspect";
          ctx = { };
        };
        state = den.lib.aspects.fx.pipeline.defaultState;
        stubs = {
          "check-dedup" =
            { param, state }:
            {
              resume = {
                isDuplicate = false;
                dedupKey = null;
              };
              inherit state;
            };
          "check-constraint" =
            { param, state }:
            {
              resume = {
                action = "allow";
              };
              inherit state;
            };
          "resolve-complete" =
            { param, state }:
            {
              resume = param;
              inherit state;
            };
          "classify" =
            { param, state }:
            {
              resume = {
                classKeys = [ ];
                nestedKeys = [ ];
              };
              inherit state;
            };
          "emit-classes" =
            { param, state }:
            {
              resume = [ ];
              inherit state;
            };
          "register-constraint" =
            { param, state }:
            {
              resume = null;
              inherit state;
            };
          # Capture the aspect in resolve-children to verify stripping.
          "resolve-children" =
            { param, state }:
            {
              resume = fx.pure param.aspect;
              inherit state;
            };
        };
        comp = fx.send "compile-static" param;
        result = fx.handle {
          handlers =
            handlers.compileStaticHandler // handlers.gateHandler // identity.collectPathsHandler // stubs;
          inherit state;
        } comp;
        resolved = builtins.head result.value;
      in
      {
        expr = (resolved ? __fn) || (resolved ? __args) || (resolved ? __parametricDepth);
        expected = false;
      }
    );

  };
}
