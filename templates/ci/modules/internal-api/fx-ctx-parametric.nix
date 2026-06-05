{
  denTest,
  lib,
  ...
}:
{
  flake.tests.fx-ctx-parametric = {

    # Bare lambda include with context arg — pipeline provides host via ctx.
    test-bare-lambda-host = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        parent = {
          name = "parent";
          meta = { };
          nixos = { };
          includes = [
            (
              { host, ... }:
              {
                nixos.networking.hostName = host;
              }
            )
          ];
        };
        comp = fx.send "resolve" {
          aspect = parent;
          identity = den.lib.aspects.fx.identity.key parent;
          ctx = { };
        };
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = {
              host = "igloo";
            };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
      in
      {
        expr = (builtins.head (builtins.head result.value).includes).nixos.networking.hostName;
        expected = "igloo";
      }
    );

    # Attrset-with-fn parametric child — explicit __args with host.
    test-attrset-functor-host = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        child = {
          name = "child";
          meta = { };
          __fn =
            { host }:
            {
              nixos.networking.hostName = host;
            };
          __args = {
            host = false;
          };
        };
        parent = {
          name = "parent";
          meta = { };
          nixos = { };
          includes = [ child ];
        };
        comp = fx.send "resolve" {
          aspect = parent;
          identity = den.lib.aspects.fx.identity.key parent;
          ctx = { };
        };
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = {
              host = "igloo";
            };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
      in
      {
        expr = (builtins.head (builtins.head result.value).includes).nixos.networking.hostName;
        expected = "igloo";
      }
    );

    # fixedTo-wrapped aspect through full pipeline with ctx — manual pipeline setup.
    test-fixedto-with-ctx = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        parametric = den.lib.parametric;
        innerAspect = {
          name = "tux";
          meta = { };
          user = {
            description = "test-user";
          };
          includes = [
            (
              { host, ... }:
              lib.optionalAttrs (host == "igloo") {
                user.extraGroups = [ "wheel" ];
              }
            )
          ];
        };
        wrapped = parametric.fixedTo {
          host = "igloo";
        } innerAspect;
        comp = fx.send "resolve" {
          aspect = wrapped;
          identity = den.lib.aspects.fx.identity.key wrapped;
          ctx = { };
        };
        # Provide host in ctx so the pipeline has a handler for it.
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "user";
            ctx = {
              host = "igloo";
            };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
      in
      {
        expr =
          builtins.length (
            (builtins.foldl' (
              acc: sd:
              lib.zipAttrsWith (_: builtins.concatLists) [
                acc
                sd
              ]
            ) { } (builtins.attrValues (result.state.scopedClassImports null))).user or [ ]
          ) > 0;
        expected = true;
      }
    );

    # fixedTo-wrapped aspect through fxResolveTree — ctx is empty, deepRecurse
    # should handle context internally without needing host in pipeline handlers.
    test-fixedto-through-fxResolveTree = denTest (
      { den, ... }:
      let
        parametric = den.lib.parametric;
        innerAspect = {
          name = "tux";
          meta = { };
          user = {
            description = "test-user";
          };
          includes = [
            (
              { host, ... }:
              lib.optionalAttrs (host == "igloo") {
                user.extraGroups = [ "wheel" ];
              }
            )
          ];
        };
        wrapped = parametric.fixedTo {
          host = "igloo";
        } innerAspect;
        # This is what forward.nix calls:
        resolved = den.lib.aspects.resolve "user" wrapped;
      in
      {
        expr = builtins.length resolved.imports > 0;
        expected = true;
      }
    );

  };
}
