{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-parametric-meta = {

    # Parametric aspect resolves functor args through the pipeline.
    test-parametric-resolves-args = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "web";
          meta = { };
          __fn =
            { host, user }:
            {
              nixos = {
                hostName = host;
                userName = user;
              };
            };
          __args = {
            host = false;
            user = false;
          };
        };
        comp = fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = {
              host = "h";
              user = "u";
            };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
      in
      {
        expr = {
          hostName = (builtins.head result.value).nixos.hostName;
          userName = (builtins.head result.value).nixos.userName;
          name = (builtins.head result.value).name;
        };
        expected = {
          hostName = "h";
          userName = "u";
          name = "web";
        };
      }
    );

    # Static aspect has no parametric meta.
    test-static-no-parametric-meta = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "base";
          meta = { };
          nixos = { };
          includes = [ ];
        };
        comp = fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
      in
      {
        expr = (builtins.head result.value).meta ? isParametric;
        expected = false;
      }
    );

    # resolve-complete carries parent info from includesChain.
    test-resolve-complete-has-parent = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        parent = {
          name = "root";
          meta = {
            provider = [ ];
          };
          includes = [
            {
              name = "child";
              meta = {
                provider = [ ];
              };
              includes = [ ];
            }
          ];
        };
        comp = fx.send "resolve" {
          aspect = parent;
          identity = den.lib.aspects.fx.identity.key parent;
          ctx = { };
        };
        result = fx.handle {
          handlers =
            den.lib.aspects.fx.pipeline.composeHandlers
              (den.lib.aspects.fx.pipeline.defaultHandlers {
                class = "nixos";
                ctx = { };
              })
              {
                "resolve-complete" =
                  { param, state }:
                  let
                    chain = ((state.scopedIncludesChain or (_: { })) null).${state.currentScope or "__unscoped"} or [ ];
                    parentName = if chain == [ ] then "ROOT" else lib.last chain;
                  in
                  {
                    resume = param;
                    state = state // {
                      parents = (state.parents or [ ]) ++ [ parentName ];
                    };
                  };
              };
          state = den.lib.aspects.fx.pipeline.defaultState // {
            parents = [ ];
          };
        } comp;
      in
      {
        # child's parent should be "root" (derived from includesChain)
        expr = builtins.elem "root" result.state.parents;
        expected = true;
      }
    );

  };
}
