{
  denTest,
  lib,
  ...
}:
{
  flake.tests.fx-compile-parametric = {

    # Parametric resolves: aspect with __args, scope handlers available →
    # gate passes, bind resolves, re-enters via resolve effect.
    test-parametric-resolves = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        identity = den.lib.aspects.fx.identity;
        aspect = {
          name = "param-aspect";
          __fn =
            { host }:
            {
              name = "resolved-${host}";
            };
          __args = {
            host = false;
          };
        };
        param = {
          inherit aspect;
          identity = "param-aspect";
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
          # Stub resolve to capture the re-entry aspect.
          "resolve" =
            { param, state }:
            {
              resume = [ param.aspect ];
              inherit state;
            };
        };
        # Provide scope handler for "host" so bind can resolve.
        comp = fx.effects.scope.provide (handlers.constantHandler { host = "igloo"; }) (
          fx.send "compile-parametric" param
        );
        result = fx.handle {
          handlers =
            handlers.compileParametricHandler
            // handlers.gateHandler
            // handlers.bindHandler
            // identity.pathSetHandler
            // identity.collectPathsHandler
            // stubs;
          inherit state;
        } comp;
        resolved = builtins.head result.value;
      in
      {
        # The re-entry aspect should have __parametricDepth incremented.
        expr = resolved.__parametricDepth or 0;
        expected = 1;
      }
    );

    # Parametric resolves: the result has parametric metadata.
    test-parametric-result-has-metadata = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        identity = den.lib.aspects.fx.identity;
        aspect = {
          name = "meta-aspect";
          __fn =
            { host }:
            {
              name = "resolved";
            };
          __args = {
            host = false;
          };
        };
        param = {
          inherit aspect;
          identity = "meta-aspect";
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
          "resolve" =
            { param, state }:
            {
              resume = [ param.aspect ];
              inherit state;
            };
        };
        comp = fx.effects.scope.provide (handlers.constantHandler { host = "igloo"; }) (
          fx.send "compile-parametric" param
        );
        result = fx.handle {
          handlers =
            handlers.compileParametricHandler
            // handlers.gateHandler
            // handlers.bindHandler
            // identity.pathSetHandler
            // identity.collectPathsHandler
            // stubs;
          inherit state;
        } comp;
        resolved = builtins.head result.value;
      in
      {
        expr = resolved.meta.isParametric or false;
        expected = true;
      }
    );

    # Parametric defers: no scope handlers → bind defers → resumes [].
    test-parametric-defers = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        identity = den.lib.aspects.fx.identity;
        aspect = {
          name = "defer-aspect";
          __fn =
            { host }:
            {
              name = "would-resolve";
            };
          __args = {
            host = false;
          };
        };
        param = {
          inherit aspect;
          identity = "defer-aspect";
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
        };
        # No scope handlers — bind will defer.
        comp = fx.send "compile-parametric" param;
        result = fx.handle {
          handlers =
            handlers.compileParametricHandler
            // handlers.gateHandler
            // handlers.bindHandler
            // handlers.deferHandler
            // identity.pathSetHandler
            // identity.collectPathsHandler
            // stubs;
          inherit state;
        } comp;
      in
      {
        expr = result.value;
        expected = [ ];
      }
    );

    # Gate blocks (dedup): resumes gate result directly.
    test-gate-blocks-dedup = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        identity = den.lib.aspects.fx.identity;
        aspect = {
          name = "dup-aspect";
          __args = {
            host = false;
          };
          __fn = { host }: { };
        };
        param = {
          inherit aspect;
          identity = "dup-aspect";
          ctx = { };
        };
        state = den.lib.aspects.fx.pipeline.defaultState;
        # Stub gate to return blocked.
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
        comp = fx.send "compile-parametric" param;
        result = fx.handle {
          handlers = handlers.compileParametricHandler // stubs;
          inherit state;
        } comp;
      in
      {
        expr = result.value;
        expected = [ ];
      }
    );

    # Depth exceeded: throws an error.
    test-depth-exceeded = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        aspect = {
          name = "deep-aspect";
          __fn = { host }: { };
          __args = {
            host = false;
          };
          __parametricDepth = 10;
        };
        param = {
          inherit aspect;
          identity = "deep-aspect";
          ctx = { };
        };
        comp = fx.send "compile-parametric" param;
        raw = fx.handle {
          handlers = handlers.compileParametricHandler;
          state = { };
        } comp;
        threw = builtins.tryEval (builtins.deepSeq raw.value raw.value);
      in
      {
        expr = threw.success;
        expected = false;
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
          __fn =
            { host }:
            {
              name = "resolved";
            };
          __args = {
            host = false;
          };
        };
        param = {
          inherit aspect;
          identity = "owned-aspect";
          ctx = { };
        };
        state = den.lib.aspects.fx.pipeline.defaultState;
        # Stub gate to pass with an owner.
        stubs = {
          "gate" =
            { param, state }:
            {
              resume = fx.pure {
                passed = true;
                owner = "constraint-xyz";
              };
              inherit state;
            };
          # Capture the aspect that bind receives to check constraintOwner.
          "bind" =
            { param, state }:
            {
              resume = fx.pure {
                value = param.aspect;
              };
              inherit state;
            };
          "resolve" =
            { param, state }:
            {
              resume = [ param.aspect ];
              inherit state;
            };
        };
        comp = fx.send "compile-parametric" param;
        result = fx.handle {
          handlers = handlers.compileParametricHandler // stubs;
          inherit state;
        } comp;
        resolved = builtins.head result.value;
      in
      {
        expr = resolved.meta.constraintOwner or null;
        expected = "constraint-xyz";
      }
    );

  };
}
