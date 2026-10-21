{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-scope-effects = {

    # push-scope: sets currentScope, registers scopeContexts, scope-local policies (no inheritance).
    test-push-scope-basic = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        pipeline = den.lib.aspects.fx.pipeline;
        parentScope = pipeline.mkScopeId { host = "alpha"; };
        scopedCtx = {
          host = "alpha";
          user = "bob";
        };
        expectedScope = pipeline.mkScopeId scopedCtx;
        baseState = pipeline.defaultState // {
          currentScope = parentScope;
          scopeContexts = _: {
            ${parentScope} = {
              host = "alpha";
            };
          };
          scopedAspectPolicies = _: {
            ${parentScope} = {
              some-policy = true;
            };
          };
        };
        comp = fx.send "push-scope" {
          inherit scopedCtx;
          entityClass = "hosts";
          inherit parentScope;
        };
        result = fx.handle {
          handlers = handlers.pushScopeHandler;
          state = baseState;
        } comp;
      in
      {
        expr = {
          scopeId = result.value.scopeId;
          hasScopeHandlers = result.value ? scopeHandlers;
          currentScope = result.state.currentScope;
          hasCtx = (result.state.scopeContexts null) ? ${expectedScope};
          # Policies no longer inherit from parent — scope-local dispatch only.
          noInheritedPolicy =
            !((result.state.scopedAspectPolicies null).${expectedScope} or { }) ? some-policy;
          hasParent = (result.state.scopeParent null) ? ${expectedScope};
        };
        expected = {
          scopeId = expectedScope;
          hasScopeHandlers = true;
          currentScope = expectedScope;
          hasCtx = true;
          noInheritedPolicy = true;
          hasParent = true;
        };
      }
    );

    # push-scope: deferred includes do NOT propagate to child scopes. Entity-arg
    # deferral is gone; deferred entries stay where they were queued. Parent keeps
    # its entry; the child gets none from inheritance.
    test-push-scope-reentry-deferred = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        pipeline = den.lib.aspects.fx.pipeline;
        parentScope = pipeline.mkScopeId { host = "alpha"; };
        scopedCtx = {
          host = "alpha";
          user = "carol";
        };
        childScope = pipeline.mkScopeId scopedCtx;
        deferred = [
          {
            child = {
              name = "d1";
            };
          }
        ];
        baseState = pipeline.defaultState // {
          currentScope = parentScope;
          scopeContexts = _: {
            ${parentScope} = {
              host = "alpha";
            };
          };
          scopedDeferredIncludes = _: { ${parentScope} = deferred; };
        };
        comp = fx.send "push-scope" {
          inherit scopedCtx parentScope;
          entityClass = null;
        };
        result = fx.handle {
          handlers = handlers.pushScopeHandler;
          state = baseState;
        } comp;
        allDeferred = result.state.scopedDeferredIncludes null;
      in
      {
        # Parent retains its 1 deferred entry; child inherits 0.
        expr = [
          (builtins.length (allDeferred.${parentScope} or [ ]))
          (builtins.length (allDeferred.${childScope} or [ ]))
        ];
        expected = [
          1
          0
        ];
      }
    );

    # push-scope: parent deferred entries are NOT fanned out to the new child
    # scope (carrier removed). The child scope sees an empty deferred list.
    test-push-scope-deferred-fanout = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        pipeline = den.lib.aspects.fx.pipeline;
        parentScope = pipeline.mkScopeId { host = "alpha"; };
        scopedCtx = {
          host = "alpha";
          user = "dave";
        };
        childScope = pipeline.mkScopeId scopedCtx;
        deferred = [
          {
            child = {
              name = "d1";
            };
          }
          {
            child = {
              name = "d2";
            };
          }
        ];
        baseState = pipeline.defaultState // {
          currentScope = parentScope;
          scopeContexts = _: {
            ${parentScope} = {
              host = "alpha";
            };
          };
          scopedDeferredIncludes = _: { ${parentScope} = deferred; };
        };
        comp = fx.send "push-scope" {
          inherit scopedCtx parentScope;
          entityClass = null;
        };
        result = fx.handle {
          handlers = handlers.pushScopeHandler;
          state = baseState;
        } comp;
      in
      {
        expr = builtins.length ((result.state.scopedDeferredIncludes null).${childScope} or [ ]);
        expected = 0;
      }
    );

    # restore-scope: restores currentScope to parentScope.
    test-restore-scope = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        pipeline = den.lib.aspects.fx.pipeline;
        parentScope = "parent-scope";
        childScope = "child-scope";
        comp = fx.send "restore-scope" { parentScope = parentScope; };
        result = fx.handle {
          handlers = handlers.restoreScopeHandler;
          state = pipeline.defaultState // {
            currentScope = childScope;
          };
        } comp;
      in
      {
        expr = {
          currentScope = result.state.currentScope;
          value = result.value;
        };
        expected = {
          currentScope = parentScope;
          value = null;
        };
      }
    );

    # push-scope then restore-scope round-trip.
    test-push-restore-roundtrip = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        pipeline = den.lib.aspects.fx.pipeline;
        parentScope = pipeline.mkScopeId { host = "alpha"; };
        scopedCtx = {
          host = "alpha";
          user = "eve";
        };
        comp = fx.bind (fx.send "push-scope" {
          inherit scopedCtx parentScope;
          entityClass = null;
        }) (_: fx.send "restore-scope" { inherit parentScope; });
        result = fx.handle {
          handlers = handlers.pushScopeHandler // handlers.restoreScopeHandler;
          state = pipeline.defaultState // {
            currentScope = parentScope;
            scopeContexts = _: {
              ${parentScope} = {
                host = "alpha";
              };
            };
          };
        } comp;
      in
      {
        expr = result.state.currentScope;
        expected = parentScope;
      }
    );

    # propagate-routes: copies matching complex root routes to child scope.
    test-propagate-routes-copies = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        pipeline = den.lib.aspects.fx.pipeline;
        rootSid = "root-scope";
        childSid = "child-scope";
        route = {
          fromClass = "hosts";
          __complexForward = true;
          name = "route-a";
        };
        baseState = pipeline.defaultState // {
          rootScopeId = rootSid;
          currentScope = childSid;
          scopedRoutes = _: { ${rootSid} = [ route ]; };
          scopedClassImports = _: {
            ${childSid} = {
              hosts = true;
            };
          };
        };
        comp = fx.send "propagate-routes" { scopeId = childSid; };
        result = fx.handle {
          handlers = handlers.propagateRoutesHandler;
          state = baseState;
        } comp;
        childRoutes = (result.state.scopedRoutes null).${childSid} or [ ];
      in
      {
        expr = {
          value = result.value;
          count = builtins.length childRoutes;
          sourceScopeId = (builtins.head childRoutes).sourceScopeId;
          name = (builtins.head childRoutes).name;
        };
        expected = {
          value = null;
          count = 1;
          sourceScopeId = childSid;
          name = "route-a";
        };
      }
    );

    # propagate-routes: no-op when no matching classes.
    test-propagate-routes-noop = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        pipeline = den.lib.aspects.fx.pipeline;
        rootSid = "root-scope";
        childSid = "child-scope";
        route = {
          fromClass = "hosts";
          __complexForward = true;
          name = "route-b";
        };
        baseState = pipeline.defaultState // {
          rootScopeId = rootSid;
          currentScope = childSid;
          scopedRoutes = _: { ${rootSid} = [ route ]; };
          # Child has no class imports for "hosts".
          scopedClassImports = _: { ${childSid} = { }; };
        };
        comp = fx.send "propagate-routes" { scopeId = childSid; };
        result = fx.handle {
          handlers = handlers.propagateRoutesHandler;
          state = baseState;
        } comp;
      in
      {
        expr = {
          value = result.value;
          childRoutes = (result.state.scopedRoutes null).${childSid} or [ ];
        };
        expected = {
          value = null;
          childRoutes = [ ];
        };
      }
    );

  };
}
