{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-includeIf = {

    test-guard-passes-includes = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        target = {
          name = "feature";
          meta = {
            provider = [ ];
          };
          nixos = {
            a = 1;
          };
          includes = [ ];
        };
        guarded = den.lib.aspects.fx.includes.includeIf (_: true) [ target ];
        parent = {
          name = "root";
          meta = { };
          includes = [ guarded ];
        };
        comp = fx.send "resolve" {
          aspect = parent;
          identity = den.lib.aspects.fx.identity.key parent;
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
        expr = (builtins.head (builtins.head result.value).includes).name;
        expected = "feature";
      }
    );

    test-guard-fails-tombstones = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        target = {
          name = "feature";
          meta = {
            provider = [ ];
          };
          includes = [ ];
        };
        guarded = den.lib.aspects.fx.includes.includeIf (_: false) [ target ];
        parent = {
          name = "root";
          meta = { };
          includes = [ guarded ];
        };
        comp = fx.send "resolve" {
          aspect = parent;
          identity = den.lib.aspects.fx.identity.key parent;
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
        expr = (builtins.head (builtins.head result.value).includes).meta.excluded;
        expected = true;
      }
    );

    test-hasAspect-guard = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        sops = {
          name = "sops";
          meta = {
            provider = [ ];
          };
          includes = [ ];
        };
        sopsConf = {
          name = "sops-conf";
          meta = {
            provider = [ ];
          };
          nixos = {
            sops = true;
          };
          includes = [ ];
        };
        guarded = den.lib.aspects.fx.includes.includeIf (ctx: ctx.hasAspect sops) [ sopsConf ];
        parent = {
          name = "root";
          meta = { };
          includes = [
            sops
            guarded
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
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
        names = map (c: c.name) (builtins.head result.value).includes;
      in
      {
        expr = builtins.elem "sops-conf" names;
        expected = true;
      }
    );

    test-hasAspect-guard-fails = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        sops = {
          name = "sops";
          meta = {
            provider = [ ];
          };
          includes = [ ];
        };
        sopsConf = {
          name = "sops-conf";
          meta = {
            provider = [ ];
          };
          includes = [ ];
        };
        guarded = den.lib.aspects.fx.includes.includeIf (ctx: ctx.hasAspect sops) [ sopsConf ];
        # sops is NOT in includes — guard should fail
        parent = {
          name = "root";
          meta = { };
          includes = [ guarded ];
        };
        comp = fx.send "resolve" {
          aspect = parent;
          identity = den.lib.aspects.fx.identity.key parent;
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
        expr = (builtins.head (builtins.head result.value).includes).meta.excluded;
        expected = true;
      }
    );

    test-fallback-pattern = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        sops = {
          name = "sops";
          meta = {
            provider = [ ];
          };
          includes = [ ];
        };
        sopsConf = {
          name = "sops-conf";
          meta = {
            provider = [ ];
          };
          nixos = { };
          includes = [ ];
        };
        ageConf = {
          name = "age-conf";
          meta = {
            provider = [ ];
          };
          nixos = { };
          includes = [ ];
        };
        parent = {
          name = "root";
          meta = { };
          includes = [
            sops
            (den.lib.aspects.fx.includes.includeIf (ctx: ctx.hasAspect sops) [ sopsConf ])
            (den.lib.aspects.fx.includes.includeIf (ctx: !ctx.hasAspect sops) [ ageConf ])
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
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
        children = (builtins.head result.value).includes;
        names = map (c: c.name) children;
      in
      {
        expr = {
          hasSopsConf = builtins.elem "sops-conf" names;
          hasAgeConf = builtins.elem "age-conf" names;
          ageExcluded =
            (lib.findFirst (c: c.name == "~age-conf") { meta = { }; } children).meta.excluded or false;
        };
        expected = {
          hasSopsConf = true;
          hasAgeConf = false;
          ageExcluded = true;
        };
      }
    );

  };
}
