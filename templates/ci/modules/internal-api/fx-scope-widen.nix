{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-scope-widen = {

    # scope-widened with no deferred items: drain returns [], resumes null.
    test-scope-widen-empty = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        comp = fx.send "scope-widened" {
          ctx = {
            host = "igloo";
          };
        };
        result = fx.handle {
          handlers =
            handlers.scopeWidenHandler
            // handlers.drainHandler
            # resolve handler stub — collect calls instead of actual resolution
            // {
              "resolve" =
                { param, state }:
                {
                  resume = param;
                  inherit state;
                };
            };
          state = {
            currentScope = "__test";
            scopedDeferredIncludes = _: { };
          };
        } comp;
      in
      {
        expr = result.value;
        expected = null;
      }
    );

    # scope-widened with satisfiable deferred: drains and re-resolves.
    test-scope-widen-drains = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        deferredChild = {
          name = "needs-host";
          meta = { };
        };
        deferred = {
          child = deferredChild;
          requiredArgs = [ "host" ];
        };
        unsatisfied = {
          child = {
            name = "needs-user";
            meta = { };
          };
          requiredArgs = [ "user" ];
        };
        resolvedAspects = builtins.listToAttrs [ ];
        comp = fx.send "scope-widened" {
          ctx = {
            host = "igloo";
          };
        };
        result = fx.handle {
          handlers =
            handlers.scopeWidenHandler
            // handlers.drainHandler
            # resolve stub — records the aspect name it was asked to resolve
            // {
              "resolve" =
                { param, state }:
                {
                  resume = {
                    resolved = param.aspect.name;
                  };
                  state = state // {
                    __resolvedNames = (state.__resolvedNames or [ ]) ++ [ param.aspect.name ];
                  };
                };
            };
          state = {
            currentScope = "__test";
            scopedDeferredIncludes = _: {
              __test = [
                deferred
                unsatisfied
              ];
            };
          };
        } comp;
      in
      {
        expr = {
          resolvedNames = result.state.__resolvedNames or [ ];
          remainingCount = builtins.length ((result.state.scopedDeferredIncludes null).__test or [ ]);
        };
        expected = {
          resolvedNames = [ "needs-host" ];
          remainingCount = 1;
        };
      }
    );

    # enterScope installs scope handlers and fires scope-widened.
    test-enterScope-fires-scope-widened = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        aspect = den.lib.aspects.fx.aspect;
        scopeHandlers = {
          host =
            { param, state }:
            {
              resume = "igloo";
              inherit state;
            };
        };
        computation = fx.send "host" null;
        comp = aspect.enterScope scopeHandlers computation;
        result = fx.handle {
          handlers =
            handlers.scopeWidenHandler
            // handlers.drainHandler
            // {
              "resolve" =
                { param, state }:
                {
                  resume = null;
                  inherit state;
                };
            };
          state = {
            currentScope = "__test";
            scopedDeferredIncludes = _: { };
          };
        } comp;
      in
      {
        expr = result.value;
        expected = "igloo";
      }
    );

  };
}
