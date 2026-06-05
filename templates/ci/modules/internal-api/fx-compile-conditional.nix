{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-compile-conditional = {

    # Guard passes: emitIncludes dispatches children.
    test-guard-passes-emits-includes = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        identity = den.lib.aspects.fx.identity;
        childAspect = {
          name = "child-a";
        };
        condNode = {
          name = "cond-node";
          meta = {
            guard = ctx: ctx.hasAspect { name = "dep-a"; };
            aspects = [ childAspect ];
          };
        };
        param = {
          aspect = condNode;
          identity = "cond-node";
          ctx = { };
        };
        state = den.lib.aspects.fx.pipeline.defaultState // {
          pathSet = _: {
            ${identity.key { name = "dep-a"; }} = true;
          };
        };
        # Stub downstream effects that emitIncludes triggers.
        stubs = {
          "get" =
            { param, state }:
            {
              resume = state;
              inherit state;
            };
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
          "resolve-aspect" =
            { param, state }:
            {
              resume = [ param ];
              inherit state;
            };
          "resolve-complete" =
            { param, state }:
            {
              resume = param;
              inherit state;
            };
        };
        comp = fx.send "compile-conditional" param;
        result = fx.handle {
          handlers =
            handlers.compileConditionalHandler
            // handlers.resolveHandler
            // handlers.compileHandler
            // handlers.gateHandler
            // handlers.compileStaticHandler
            // handlers.compileParametricHandler
            // handlers.compileForwardHandler
            // handlers.bindHandler
            // handlers.deferHandler
            // handlers.drainHandler
            // handlers.classifyHandler
            // handlers.emitClassesHandler
            // handlers.resolveChildrenHandler
            // handlers.checkDedupHandler
            // handlers.chainHandler
            // identity.pathSetHandler
            // identity.collectPathsHandler
            // stubs
            // fx.effects.state.handler;
          inherit state;
        } comp;
      in
      {
        expr = builtins.length result.value;
        expected = 1;
      }
    );

    # Guard fails: tombstones are created for all child aspects.
    test-guard-fails-creates-tombstones = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        identity = den.lib.aspects.fx.identity;
        childA = {
          name = "child-a";
        };
        childB = {
          name = "child-b";
        };
        condNode = {
          name = "cond-node";
          meta = {
            guard = ctx: ctx.hasAspect { name = "missing-dep"; };
            aspects = [
              childA
              childB
            ];
          };
        };
        param = {
          aspect = condNode;
          identity = "cond-node";
          ctx = { };
        };
        # Empty path-set — guard will fail.
        state = den.lib.aspects.fx.pipeline.defaultState;
        stubs = {
          "resolve-complete" =
            { param, state }:
            {
              resume = param;
              inherit state;
            };
        };
        comp = fx.bind (fx.send "compile-conditional" param) (_: fx.send "drain-conditionals" null);
        result = fx.handle {
          handlers =
            handlers.compileConditionalHandler
            // handlers.deferConditionalHandler
            // handlers.drainConditionalsHandler
            // identity.pathSetHandler
            // stubs
            // fx.effects.state.handler;
          inherit state;
        } comp;
        tombstones = result.value;
      in
      {
        expr = map (t: t.meta.excluded) tombstones;
        expected = [
          true
          true
        ];
      }
    );

    # Guard fails: tombstone names are prefixed with ~.
    test-tombstone-names = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        identity = den.lib.aspects.fx.identity;
        condNode = {
          name = "cond-node";
          meta = {
            guard = _: false;
            aspects = [
              { name = "alpha"; }
              { name = "beta"; }
            ];
          };
        };
        param = {
          aspect = condNode;
          identity = "cond-node";
          ctx = { };
        };
        state = den.lib.aspects.fx.pipeline.defaultState;
        stubs = {
          "resolve-complete" =
            { param, state }:
            {
              resume = param;
              inherit state;
            };
        };
        comp = fx.bind (fx.send "compile-conditional" param) (
          _:
          # Drain deferred conditionals to produce tombstones.
          fx.send "drain-conditionals" null
        );
        result = fx.handle {
          handlers =
            handlers.compileConditionalHandler
            // handlers.deferConditionalHandler
            // handlers.drainConditionalsHandler
            // identity.pathSetHandler
            // stubs
            // fx.effects.state.handler;
          inherit state;
        } comp;
      in
      {
        expr = map (t: t.name) result.value;
        expected = [
          "~alpha"
          "~beta"
        ];
      }
    );

    # Scope handlers are propagated from condNode to children.
    test-scope-propagation = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        identity = den.lib.aspects.fx.identity;
        condNode = {
          name = "cond-scope";
          __scopeHandlers = {
            myHandler = true;
          };
          __ctxId = "ctx-42";
          meta = {
            guard = _: true;
            aspects = [
              { name = "scoped-child"; }
            ];
          };
        };
        param = {
          aspect = condNode;
          identity = "cond-scope";
          ctx = { };
        };
        # Capture the aspect that resolve-aspect receives.
        captured = builtins.unsafeGetAttrPos "capture" {
          capture = null;
        };
        state = den.lib.aspects.fx.pipeline.defaultState // {
          pathSet = _: {
            "anything" = true;
          };
        };
        stubs = {
          "get" =
            { param, state }:
            {
              resume = state;
              inherit state;
            };
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
          "resolve-aspect" =
            { param, state }:
            {
              # Return the aspect wrapped in a list so emitIncludes can collect it.
              resume = [ param ];
              inherit state;
            };
          "resolve-complete" =
            { param, state }:
            {
              resume = param;
              inherit state;
            };
        };
        comp = fx.send "compile-conditional" param;
        result = fx.handle {
          handlers =
            handlers.compileConditionalHandler
            // handlers.resolveHandler
            // handlers.compileHandler
            // handlers.gateHandler
            // handlers.compileStaticHandler
            // handlers.compileParametricHandler
            // handlers.compileForwardHandler
            // handlers.bindHandler
            // handlers.deferHandler
            // handlers.drainHandler
            // handlers.classifyHandler
            // handlers.emitClassesHandler
            // handlers.resolveChildrenHandler
            // handlers.checkDedupHandler
            // handlers.chainHandler
            // identity.pathSetHandler
            // identity.collectPathsHandler
            // stubs
            // fx.effects.state.handler;
          inherit state;
        } comp;
        child = builtins.head result.value;
      in
      {
        expr = child.__scopeHandlers or null;
        expected = {
          myHandler = true;
        };
      }
    );

  };
}
