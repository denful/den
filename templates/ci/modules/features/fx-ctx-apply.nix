# Tests for context traversal helpers: emitAspectPolicies, dedup.
{
  denTest,
  inputs,
  lib,
  ...
}:
let

  collectHandlers = {
    "emit-class" =
      { param, state }:
      {
        resume = null;
        inherit state;
      };
    "emit-include" =
      { param, state }:
      {
        resume = [ param ];
        inherit state;
      };
    "into-transition" =
      { param, state }:
      {
        resume = [ ];
        state = state // {
          transitions = (state.transitions or [ ]) ++ [
            {
              hasIntoFn = param ? intoFn;
              selfName = param.self.name or "<anon>";
            }
          ];
        };
      };
    "register-constraint" =
      { param, state }:
      {
        resume = null;
        inherit state;
      };
    "chain-push" =
      { param, state }:
      {
        resume = null;
        inherit state;
      };
    "chain-pop" =
      { param, state }:
      {
        resume = null;
        inherit state;
      };
    "resolve-complete" =
      { param, state }:
      {
        resume = param;
        inherit state;
      };
  };
in
{
  flake.tests.fx-ctx-apply = {

    # emitAspectPolicies: produces include from aspect.provides.${name} (self-provide).
    test-self-provide = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "host";
          meta = { };
          provides = {
            host = ctx: {
              name = "host-provider";
              meta = { };
              nixos = {
                provided = true;
              };
              includes = [ ];
            };
          };
          includes = [ ];
        };
        comp = den.lib.aspects.fx.aspect.emitAspectPolicies aspect;
        result = fx.handle {
          handlers = collectHandlers;
          state = { };
        } comp;
      in
      {
        expr = {
          hasResult = builtins.isList result.value && builtins.length result.value >= 1;
          firstName = (builtins.head result.value).name;
        };
        expected = {
          hasResult = true;
          firstName = "host";
        };
      }
    );

    # Into keys excluded from class emission by structuralKeys.
    test-into-not-class = denTest (
      { den, ... }:
      let
        pipeline = den.lib.aspects.fx.pipeline;
        aspect = {
          name = "host";
          meta = { };
          into = _: { };
          nixos = {
            enable = true;
          };
          includes = [ ];
        };
        result = pipeline.fxFullResolve {
          class = "nixos";
          self = aspect;
          ctx = { };
        };
        scoped = result.state.scopedClassImports null;
        flat = builtins.foldl' (
          acc: sd:
          lib.zipAttrsWith (_: builtins.concatLists) [
            acc
            sd
          ]
        ) { } (builtins.attrValues scoped);
        classNames = builtins.attrNames flat;
      in
      {
        expr = classNames;
        expected = [ "nixos" ];
      }
    );

    # emitAspectPolicies returns empty when no matching provide.
    test-self-provide-absent = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "host";
          meta = { };
          provides = { };
          includes = [ ];
        };
        comp = den.lib.aspects.fx.aspect.emitAspectPolicies aspect;
        result = fx.handle {
          handlers = collectHandlers;
          state = { };
        } comp;
      in
      {
        expr = result.value;
        expected = [ ];
      }
    );

    # Functor resolution preserves into and provides.
    test-functor-preserves-into = denTest (
      { den, ... }:
      let
        pipeline = den.lib.aspects.fx.pipeline;
        aspect = {
          name = "host";
          meta = { };
          into = ctx: {
            user = [ { user = "tux"; } ];
          };
          __fn =
            { host }:
            {
              nixos = {
                hostName = host;
              };
              includes = [ ];
            };
          __args = {
            host = false;
          };
        };
        result = pipeline.fxFullResolve {
          class = "nixos";
          self = aspect;
          ctx = {
            host = "igloo";
          };
        };
        resolved = builtins.head result.value;
      in
      {
        # Verify into is preserved through functor resolution
        # (the resolved aspect still has into, visible via structural attrs)
        expr = resolved ? into;
        expected = true;
      }
    );

    # Dedup: same key second time gets isFirst=false (standalone test).
    test-dedup = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        comp = fx.bind (fx.send "ctx-seen" "k") (
          a:
          fx.bind (fx.send "ctx-seen" "k") (
            b:
            fx.pure {
              first = a.isFirst;
              second = b.isFirst;
            }
          )
        );
        result = fx.handle {
          handlers."ctx-seen" =
            { param, state }:
            let
              isFirst = !(((state.seen or (_: { })) null) ? ${param});
            in
            {
              resume = { inherit isFirst; };
              state = state // {
                seen =
                  _:
                  ((state.seen or (_: { })) null)
                  // {
                    ${param} = true;
                  };
              };
            };
          state = {
            seen = _: { };
          };
        } comp;
      in
      {
        expr = result.value;
        expected = {
          first = true;
          second = false;
        };
      }
    );

    # Self-provider standalone: ctx-provider effect resolves provides.
    test-self-provider = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        provFn = ctx: { name = "provided"; };
        comp = fx.send "ctx-provider" {
          kind = "self";
          self = {
            name = "host";
            provides = {
              host = provFn;
            };
          };
          ctx = { };
          key = "host";
          prev = null;
          prevCtx = null;
        };
        result = fx.handle {
          handlers."ctx-provider" =
            { param, state }:
            if param.kind == "self" then
              {
                resume = param.self.provides.${param.self.name} or null;
                inherit state;
              }
            else
              {
                resume = null;
                inherit state;
              };
          state = { };
        } comp;
      in
      {
        expr = (result.value { }).name;
        expected = "provided";
      }
    );

  };
}
