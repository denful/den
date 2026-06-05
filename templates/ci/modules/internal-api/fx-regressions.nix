{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-regressions = {

    # #413/#423: Provider sub-aspect's includes contain parametric fns.
    # Old pipeline: context dropped during recursive descent.
    # Effects: each level independently sends what it needs.
    test-provider-sub-includes-get-context = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        inner =
          { host }:
          {
            nixos.networking.hostName = host;
          };
        provider = {
          name = "monitoring";
          meta = {
            provider = [ ];
          };
          includes = [ inner ];
        };
        comp = fx.send "resolve" {
          aspect = provider;
          identity = den.lib.aspects.fx.identity.key provider;
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
        child = builtins.head (builtins.head result.value).includes;
      in
      {
        expr = child.nixos.networking.hostName;
        expected = "igloo";
      }
    );

    # #426: Static sub inside parametric parent. applyDeep dropped static subs.
    # Effects: static subs have no parametric args, body passes through.
    test-static-sub-preserves-owned = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        staticBase = {
          name = "base";
          meta = { };
          nixos = {
            programs.git.enable = true;
          };
          includes = [ ];
        };
        parametricDev = {
          name = "dev";
          meta = { };
          __fn =
            { user }:
            {
              includes = [ staticBase ];
            };
          __args = {
            user = false;
          };
        };
        comp = fx.send "resolve" {
          aspect = parametricDev;
          identity = den.lib.aspects.fx.identity.key parametricDev;
          ctx = { };
        };
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = {
              user = "tux";
            };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
        child = builtins.head (builtins.head result.value).includes;
      in
      {
        expr = child.nixos.programs.git.enable;
        expected = true;
      }
    );

    # #437: Factory function resolved as static (pre-applied by user).
    test-factory-resolves-as-static = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        factoryResult = {
          name = "greeter";
          meta = { };
          nixos = {
            users.users.tux.description = "hello";
          };
          includes = [ ];
        };
        comp = fx.send "resolve" {
          aspect = factoryResult;
          identity = den.lib.aspects.fx.identity.key factoryResult;
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
        expr = (builtins.head result.value).nixos.users.users.tux.description;
        expected = "hello";
      }
    );

    # Meta carryover: meta.provider survives deep resolution.
    test-meta-provider-survives = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        child = {
          name = "sub";
          meta = {
            provider = [ "monitoring" ];
          };
          nixos = { };
          includes = [ ];
        };
        parent = {
          name = "monitoring";
          meta = {
            provider = [ ];
          };
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
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
        childResult = builtins.head (builtins.head result.value).includes;
      in
      {
        expr = childResult.meta.provider;
        expected = [ "monitoring" ];
      }
    );

    # 3-level deep nesting with parametric at each level.
    test-three-level-deep-parametric = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        leaf =
          { host }:
          {
            nixos.networking.hostName = host;
          };
        mid = {
          name = "mid";
          meta = { };
          __fn =
            { user }:
            {
              includes = [ leaf ];
            };
          __args = {
            user = false;
          };
        };
        root = {
          name = "root";
          meta = { };
          includes = [ mid ];
        };
        comp = fx.send "resolve" {
          aspect = root;
          identity = den.lib.aspects.fx.identity.key root;
          ctx = { };
        };
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = {
              host = "igloo";
              user = "tux";
            };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
        midResult = builtins.head (builtins.head result.value).includes;
        leafResult = builtins.head midResult.includes;
      in
      {
        expr = leafResult.nixos.networking.hostName;
        expected = "igloo";
      }
    );

  };
}
