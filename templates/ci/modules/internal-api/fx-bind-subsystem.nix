{
  denTest,
  lib,
  ...
}:
{
  flake.tests.fx-bind-subsystem = {

    # bind: all required args have scope handlers → calls compileFn, returns { value }.
    test-bind-all-available = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        aspect = {
          name = "test-aspect";
          __fn =
            { host, user }:
            {
              inherit host user;
            };
          __args = {
            host = false;
            user = false;
          };
        };
        compileFn = a: fx.pure { compiled = a.name; };
        # Provide scope handlers for host and user so hasHandler returns true.
        comp = fx.effects.scope.provide (handlers.constantHandler {
          host = "igloo";
          user = "tux";
        }) (fx.send "bind" { inherit aspect compileFn; });
        result = fx.handle {
          handlers = handlers.bindHandler;
          state = { };
        } comp;
      in
      {
        expr = result.value;
        expected = {
          value = {
            compiled = "test-aspect";
          };
        };
      }
    );

    # bind: missing scope handlers for required args → defers, returns { deferred = true }.
    test-bind-defers-missing = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        aspect = {
          name = "needs-host";
          __fn =
            { host }:
            {
              inherit host;
            };
          __args = {
            host = false;
          };
        };
        compileFn = _: fx.pure { compiled = true; };
        # No scope handlers provided, so hasHandler will return false.
        # We need a handler for "defer" since bind sends it.
        deferSink = {
          "defer" =
            { param, state }:
            {
              resume = null;
              inherit state;
            };
        };
        comp = fx.send "bind" { inherit aspect compileFn; };
        result = fx.handle {
          handlers = handlers.bindHandler // deferSink;
          state = { };
        } comp;
      in
      {
        expr = result.value;
        expected = {
          deferred = true;
        };
      }
    );

    # bind: aspect with __scopeHandlers skips probing for those keys.
    test-bind-skips-scope-handlers = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        aspect = {
          name = "has-own-scope";
          __fn =
            { host, local }:
            {
              inherit host local;
            };
          __args = {
            host = false;
            local = false;
          };
          # local is provided by the aspect's own scope handlers, no probing needed.
          __scopeHandlers = {
            local =
              { param, state }:
              {
                resume = "self-provided";
                inherit state;
              };
          };
        };
        compileFn = a: fx.pure { compiled = a.name; };
        # Only provide host — local should be skipped via __scopeHandlers.
        comp = fx.effects.scope.provide (handlers.constantHandler { host = "igloo"; }) (
          fx.send "bind" { inherit aspect compileFn; }
        );
        result = fx.handle {
          handlers = handlers.bindHandler;
          state = { };
        } comp;
      in
      {
        expr = result.value;
        expected = {
          value = {
            compiled = "has-own-scope";
          };
        };
      }
    );

    # defer: queues in scopedDeferredIncludes, emits resolve-complete stub.
    test-defer-queues-and-stubs = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        child = {
          name = "deferred-child";
          meta = {
            provider = [ "test" ];
          };
        };
        # Capture the resolve-complete stub.
        stubCapture = {
          "resolve-complete" =
            { param, state }:
            {
              resume = param;
              state = state // {
                capturedStub = param;
              };
            };
        };
        comp = fx.send "defer" {
          inherit child;
          requiredKeys = [ "host" ];
          requiredArgs = [ "host" ];
        };
        result = fx.handle {
          handlers = handlers.deferHandler // stubCapture;
          state = {
            currentScope = "__test";
            scopedDeferredIncludes = _: { };
          };
        } comp;
        queued = (result.state.scopedDeferredIncludes null).__test or [ ];
        stub = result.state.capturedStub;
      in
      {
        expr = {
          queuedCount = builtins.length queued;
          queuedChildName = (builtins.head queued).child.name;
          stubName = stub.name;
          stubDeferred = stub.meta.deferred;
          stubIncludes = stub.includes;
          # Provider from original meta should be preserved.
          stubProvider = stub.meta.provider;
        };
        expected = {
          queuedCount = 1;
          queuedChildName = "deferred-child";
          stubName = "deferred-child";
          stubDeferred = true;
          stubIncludes = [ ];
          stubProvider = [ "test" ];
        };
      }
    );

    # drain: partitions by ctx satisfiability, returns satisfiable, keeps remaining.
    test-drain-partitions = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        deferredA = {
          child = {
            name = "needs-host";
          };
          requiredArgs = [ "host" ];
        };
        deferredB = {
          child = {
            name = "needs-user";
          };
          requiredArgs = [ "user" ];
        };
        comp = fx.send "drain" { host = { }; };
        result = fx.handle {
          handlers = handlers.drainHandler;
          state = {
            currentScope = "__test";
            scopedDeferredIncludes = _: {
              __test = [
                deferredA
                deferredB
              ];
            };
          };
        } comp;
        satisfiable = result.value;
        remaining = (result.state.scopedDeferredIncludes null).__test or [ ];
      in
      {
        expr = {
          satisfiedCount = builtins.length satisfiable;
          satisfiedName = (builtins.head satisfiable).child.name;
          remainingCount = builtins.length remaining;
          remainingName = (builtins.head remaining).child.name;
        };
        expected = {
          satisfiedCount = 1;
          satisfiedName = "needs-host";
          remainingCount = 1;
          remainingName = "needs-user";
        };
      }
    );

    # drain: empty ctx returns nothing, all remain queued.
    test-drain-empty-ctx = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        deferred = {
          child = {
            name = "needs-host";
          };
          requiredArgs = [ "host" ];
        };
        comp = fx.send "drain" { };
        result = fx.handle {
          handlers = handlers.drainHandler;
          state = {
            currentScope = "__test";
            scopedDeferredIncludes = _: {
              __test = [ deferred ];
            };
          };
        } comp;
      in
      {
        expr = {
          satisfiedCount = builtins.length result.value;
          remainingCount = builtins.length ((result.state.scopedDeferredIncludes null).__test or [ ]);
        };
        expected = {
          satisfiedCount = 0;
          remainingCount = 1;
        };
      }
    );

    # drain: empty queue returns empty list.
    test-drain-empty-queue = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        comp = fx.send "drain" { host = "igloo"; };
        result = fx.handle {
          handlers = handlers.drainHandler;
          state = {
            currentScope = "__test";
            scopedDeferredIncludes = _: { };
          };
        } comp;
      in
      {
        expr = result.value;
        expected = [ ];
      }
    );

  };
}
