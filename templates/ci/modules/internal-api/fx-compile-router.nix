{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-compile-router = {

    # resolve sends compile, which routes static aspects to compile-static.
    test-resolve-routes-static = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        stubs = {
          "compile-forward" =
            { param, state }:
            {
              resume = fx.pure "forward";
              inherit state;
            };
          "compile-conditional" =
            { param, state }:
            {
              resume = fx.pure "conditional";
              inherit state;
            };
          "compile-parametric" =
            { param, state }:
            {
              resume = fx.pure "parametric";
              inherit state;
            };
          "compile-static" =
            { param, state }:
            {
              resume = fx.pure "static";
              inherit state;
            };
        };
        aspect = {
          name = "plain";
        };
        comp = fx.send "resolve" {
          inherit aspect;
          identity = "plain";
          ctx = { };
        };
        result = fx.handle {
          handlers = handlers.resolveHandler // handlers.compileHandler // stubs;
          state = { };
        } comp;
      in
      {
        expr = result.value;
        expected = "static";
      }
    );

    # Aspect with meta.__forward routes to compile-forward.
    test-resolve-routes-forward = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        stubs = {
          "compile-forward" =
            { param, state }:
            {
              resume = fx.pure "forward";
              inherit state;
            };
          "compile-conditional" =
            { param, state }:
            {
              resume = fx.pure "conditional";
              inherit state;
            };
          "compile-parametric" =
            { param, state }:
            {
              resume = fx.pure "parametric";
              inherit state;
            };
          "compile-static" =
            { param, state }:
            {
              resume = fx.pure "static";
              inherit state;
            };
        };
        aspect = {
          name = "fwd";
          meta.__forward = true;
        };
        comp = fx.send "resolve" {
          inherit aspect;
          identity = "fwd";
          ctx = { };
        };
        result = fx.handle {
          handlers = handlers.resolveHandler // handlers.compileHandler // stubs;
          state = { };
        } comp;
      in
      {
        expr = result.value;
        expected = "forward";
      }
    );

    # Aspect with meta.guard routes to compile-conditional.
    test-resolve-routes-conditional = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        stubs = {
          "compile-forward" =
            { param, state }:
            {
              resume = fx.pure "forward";
              inherit state;
            };
          "compile-conditional" =
            { param, state }:
            {
              resume = fx.pure "conditional";
              inherit state;
            };
          "compile-parametric" =
            { param, state }:
            {
              resume = fx.pure "parametric";
              inherit state;
            };
          "compile-static" =
            { param, state }:
            {
              resume = fx.pure "static";
              inherit state;
            };
        };
        aspect = {
          name = "cond";
          meta.guard = _: true;
        };
        comp = fx.send "resolve" {
          inherit aspect;
          identity = "cond";
          ctx = { };
        };
        result = fx.handle {
          handlers = handlers.resolveHandler // handlers.compileHandler // stubs;
          state = { };
        } comp;
      in
      {
        expr = result.value;
        expected = "conditional";
      }
    );

    # Aspect with __args routes to compile-parametric.
    test-resolve-routes-parametric = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        stubs = {
          "compile-forward" =
            { param, state }:
            {
              resume = fx.pure "forward";
              inherit state;
            };
          "compile-conditional" =
            { param, state }:
            {
              resume = fx.pure "conditional";
              inherit state;
            };
          "compile-parametric" =
            { param, state }:
            {
              resume = fx.pure "parametric";
              inherit state;
            };
          "compile-static" =
            { param, state }:
            {
              resume = fx.pure "static";
              inherit state;
            };
        };
        aspect = {
          name = "param";
          __args = {
            x = 1;
          };
        };
        comp = fx.send "resolve" {
          inherit aspect;
          identity = "param";
          ctx = { };
        };
        result = fx.handle {
          handlers = handlers.resolveHandler // handlers.compileHandler // stubs;
          state = { };
        } comp;
      in
      {
        expr = result.value;
        expected = "parametric";
      }
    );

    # Forward takes precedence over guard when both are present.
    test-forward-precedence-over-guard = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        stubs = {
          "compile-forward" =
            { param, state }:
            {
              resume = fx.pure "forward";
              inherit state;
            };
          "compile-conditional" =
            { param, state }:
            {
              resume = fx.pure "conditional";
              inherit state;
            };
          "compile-parametric" =
            { param, state }:
            {
              resume = fx.pure "parametric";
              inherit state;
            };
          "compile-static" =
            { param, state }:
            {
              resume = fx.pure "static";
              inherit state;
            };
        };
        aspect = {
          name = "both";
          meta = {
            __forward = true;
            guard = _: true;
          };
        };
        comp = fx.send "resolve" {
          inherit aspect;
          identity = "both";
          ctx = { };
        };
        result = fx.handle {
          handlers = handlers.resolveHandler // handlers.compileHandler // stubs;
          state = { };
        } comp;
      in
      {
        expr = result.value;
        expected = "forward";
      }
    );

  };
}
