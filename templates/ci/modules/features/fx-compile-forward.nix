{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-compile-forward = {

    # Tier 1: simple forward with source already collected → simple route.
    test-tier1-simple-route = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        spec = {
          canDirectImport = true;
          needsAdapter = false;
          fromClass = "hosts";
          intoClass = "users";
          staticIntoPath = [
            "programs"
            "git"
          ];
          sourceAspect = { };
        };
        param = {
          aspect = {
            name = "fwd-simple";
            meta.__forward = spec;
          };
          identity = "fwd-simple";
          ctx = { };
        };
        state = den.lib.aspects.fx.pipeline.defaultState // {
          currentScope = "test-scope";
          scopedClassImports = _: {
            "test-scope" = {
              hosts = true;
            };
          };
        };
        comp = fx.send "compile-forward" param;
        result = fx.handle {
          handlers = handlers.compileForwardHandler;
          inherit state;
        } comp;
      in
      {
        expr = result.value;
        expected = [ ];
      }
    );

    # Tier 1: verify route shape stored in state.
    test-tier1-route-shape = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        spec = {
          canDirectImport = true;
          needsAdapter = false;
          fromClass = "hosts";
          intoClass = "users";
          staticIntoPath = [
            "programs"
            "git"
          ];
          sourceAspect = { };
        };
        param = {
          aspect = {
            name = "fwd-simple";
            meta.__forward = spec;
          };
          identity = "fwd-simple";
          ctx = { };
        };
        state = den.lib.aspects.fx.pipeline.defaultState // {
          currentScope = "test-scope";
          scopedClassImports = _: {
            "test-scope" = {
              hosts = true;
            };
          };
        };
        comp = fx.send "compile-forward" param;
        result = fx.handle {
          handlers = handlers.compileForwardHandler;
          inherit state;
        } comp;
        routes = (result.state.scopedRoutes null)."test-scope";
      in
      {
        expr = builtins.head routes;
        expected = {
          fromClass = "hosts";
          intoClass = "users";
          path = [
            "programs"
            "git"
          ];
          guard = null;
          adaptArgs = null;
          sourceScopeId = "test-scope";
        };
      }
    );

    # Complex: forward with adapter → complex route with __complexForward.
    test-complex-route-with-adapter = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        spec = {
          canDirectImport = true;
          needsAdapter = true;
          fromClass = "hosts";
          intoClass = "users";
          staticIntoPath = [
            "programs"
            "git"
          ];
          sourceAspect = { };
        };
        param = {
          aspect = {
            name = "fwd-complex";
            meta.__forward = spec;
          };
          identity = "fwd-complex";
          ctx = { };
        };
        state = den.lib.aspects.fx.pipeline.defaultState // {
          currentScope = "test-scope";
          scopedClassImports = _: {
            "test-scope" = {
              hosts = true;
            };
          };
        };
        comp = fx.send "compile-forward" param;
        result = fx.handle {
          handlers = handlers.compileForwardHandler;
          inherit state;
        } comp;
        routes = (result.state.scopedRoutes null)."test-scope";
        route = builtins.head routes;
      in
      {
        expr = route.__complexForward;
        expected = true;
      }
    );

    # Complex: source not yet collected → complex route.
    test-complex-route-source-missing = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        spec = {
          canDirectImport = true;
          needsAdapter = false;
          fromClass = "hosts";
          intoClass = "users";
          staticIntoPath = [
            "programs"
            "git"
          ];
          sourceAspect = { };
        };
        param = {
          aspect = {
            name = "fwd-uncollected";
            meta.__forward = spec;
          };
          identity = "fwd-uncollected";
          ctx = { };
        };
        # No hosts in scopedClassImports → source not collected → complex.
        state = den.lib.aspects.fx.pipeline.defaultState // {
          currentScope = "test-scope";
        };
        comp = fx.send "compile-forward" param;
        result = fx.handle {
          handlers = handlers.compileForwardHandler;
          inherit state;
        } comp;
        routes = (result.state.scopedRoutes null)."test-scope";
        route = builtins.head routes;
      in
      {
        expr = route.__complexForward;
        expected = true;
      }
    );

    # Complex: source aspect has __scopeHandlers → non-local → complex.
    test-complex-route-nonlocal-source = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        spec = {
          canDirectImport = true;
          needsAdapter = false;
          fromClass = "hosts";
          intoClass = "users";
          staticIntoPath = [
            "programs"
            "git"
          ];
          sourceAspect = {
            __scopeHandlers = {
              some = true;
            };
          };
        };
        param = {
          aspect = {
            name = "fwd-nonlocal";
            meta.__forward = spec;
          };
          identity = "fwd-nonlocal";
          ctx = { };
        };
        state = den.lib.aspects.fx.pipeline.defaultState // {
          currentScope = "test-scope";
          scopedClassImports = _: {
            "test-scope" = {
              hosts = true;
            };
          };
        };
        comp = fx.send "compile-forward" param;
        result = fx.handle {
          handlers = handlers.compileForwardHandler;
          inherit state;
        } comp;
        routes = (result.state.scopedRoutes null)."test-scope";
        route = builtins.head routes;
      in
      {
        expr = route.__complexForward;
        expected = true;
      }
    );

    # Resume value is always [] (empty list), never null.
    test-resume-is-empty-list = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        spec = {
          canDirectImport = false;
          needsAdapter = false;
          fromClass = "hosts";
          intoClass = "users";
          staticIntoPath = [ "x" ];
          sourceAspect = { };
        };
        param = {
          aspect = {
            name = "fwd-resume";
            meta.__forward = spec;
          };
          identity = "fwd-resume";
          ctx = { };
        };
        state = den.lib.aspects.fx.pipeline.defaultState // {
          currentScope = "s";
        };
        comp = fx.send "compile-forward" param;
        result = fx.handle {
          handlers = handlers.compileForwardHandler;
          inherit state;
        } comp;
      in
      {
        expr = builtins.isList result.value;
        expected = true;
      }
    );

  };
}
