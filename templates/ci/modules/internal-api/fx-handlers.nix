{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-handlers = {

    # constantHandler resumes with ctx value for known arg.
    test-parametric-handler-provides-value = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        ctx = {
          host = "igloo";
          user = "tux";
        };
        handlers = builtins.mapAttrs (
          name: value:
          { param, state }:
          {
            resume = value;
            inherit state;
          }
        ) ctx;
        comp = fx.send "host" false;
        result = fx.handle {
          inherit handlers;
          state = { };
        } comp;
      in
      {
        expr = result.value;
        expected = "igloo";
      }
    );

    # constantHandler provides class.
    test-static-handler-provides-class = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = {
          "class" =
            { param, state }:
            {
              resume = "nixos";
              inherit state;
            };
        };
        comp = fx.send "class" false;
        result = fx.handle {
          inherit handlers;
          state = { };
        } comp;
      in
      {
        expr = result.value;
        expected = "nixos";
      }
    );

    # Combined handlers: constantHandler merges ctx + static in one handle call.
    test-combined-handlers = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        ctx = {
          host = "igloo";
        };
        parametric = builtins.mapAttrs (
          _: v:
          { param, state }:
          {
            resume = v;
            inherit state;
          }
        ) ctx;
        static = {
          "class" =
            { param, state }:
            {
              resume = "nixos";
              inherit state;
            };
        };
        aspect =
          { host, class }:
          {
            hostName = host;
            cls = class;
          };
        comp = fx.bind.fn { } aspect;
        result = fx.handle {
          handlers = parametric // static;
          state = { };
        } comp;
      in
      {
        expr = result.value;
        expected = {
          hostName = "igloo";
          cls = "nixos";
        };
      }
    );

    # Two-layer topology: rotate handles known, outer catches unknown.
    test-rotate-unknown-to-outer = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        ctx = {
          host = "igloo";
        };
        parametric = builtins.mapAttrs (
          _: v:
          { param, state }:
          {
            resume = v;
            inherit state;
          }
        ) ctx;
        aspect =
          { host, missing-arg }:
          {
            inherit host missing-arg;
          };
        comp = fx.bind.fn { } aspect;
        inner = fx.rotate {
          handlers = parametric;
          state = { };
        } comp;
        result = fx.handle {
          handlers."missing-arg" =
            { param, state }:
            {
              resume = "caught";
              inherit state;
            };
          state = { };
        } inner;
      in
      {
        expr = result.value.value;
        expected = {
          host = "igloo";
          missing-arg = "caught";
        };
      }
    );

    # constantHandler merges ctx values.
    test-constantHandler-denTest = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers.constantHandler {
          host = "igloo";
          class = "nixos";
        };
        aspect =
          { host, class }:
          {
            hostName = host;
            cls = class;
          };
        comp = fx.bind.fn { } aspect;
        result = fx.handle {
          inherit handlers;
          state = { };
        } comp;
      in
      {
        expr = result.value;
        expected = {
          hostName = "igloo";
          cls = "nixos";
        };
      }
    );

    # chainHandler: push appends identity to includesChain.
    test-chain-push-appends = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        comp = fx.bind (fx.send "chain-push" { identity = "a"; }) (
          _: fx.send "chain-push" { identity = "b"; }
        );
        result = fx.handle {
          handlers = den.lib.aspects.fx.handlers.chainHandler;
          state = {
            currentScope = "__test";
            scopedIncludesChain = _: { };
          };
        } comp;
      in
      {
        expr = (result.state.scopedIncludesChain null).__test or [ ];
        expected = [
          "a"
          "b"
        ];
      }
    );

    # chainHandler: pop removes last element.
    test-chain-pop-removes-last = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        comp = fx.bind (fx.send "chain-push" { identity = "a"; }) (
          _: fx.bind (fx.send "chain-push" { identity = "b"; }) (_: fx.send "chain-pop" null)
        );
        result = fx.handle {
          handlers = den.lib.aspects.fx.handlers.chainHandler;
          state = {
            currentScope = "__test";
            scopedIncludesChain = _: { };
          };
        } comp;
      in
      {
        expr = (result.state.scopedIncludesChain null).__test or [ ];
        expected = [ "a" ];
      }
    );

    # chainHandler: pop on empty list throws (push/pop mismatch).
    test-chain-pop-empty-throws = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        comp = fx.send "chain-pop" null;
        raw = fx.handle {
          handlers = den.lib.aspects.fx.handlers.chainHandler;
          state = {
            currentScope = "__test";
            scopedIncludesChain = _: { };
          };
        } comp;
        # Force the scopedIncludesChain thunk inside tryEval to catch the throw.
        result = builtins.tryEval (
          builtins.deepSeq ((raw.state.scopedIncludesChain) null) ((raw.state.scopedIncludesChain) null)
        );
      in
      {
        expr = result.success;
        expected = false;
      }
    );

    # --- ctx-seen handler tests ---

    # ctx-seen tracks seen keys and reports isFirst correctly.
    test-ctx-seen-dedup = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        comp = fx.bind (fx.send "ctx-seen" "key-a") (
          first:
          fx.bind (fx.send "ctx-seen" "key-b") (
            second:
            fx.bind (fx.send "ctx-seen" "key-a") (
              third:
              fx.pure [
                first
                second
                third
              ]
            )
          )
        );
        result = fx.handle {
          handlers = handlers.ctxSeenHandler;
          state = {
            seen = _: { };
          };
        } comp;
      in
      {
        expr = map (r: r.isFirst) result.value;
        expected = [
          true
          true
          false
        ];
      }
    );

    # --- emit-class / classCollectorHandler tests ---

    # classCollectorHandler collects matching class, skips others.
    test-class-collector-filters = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        comp = fx.seq [
          (fx.send "emit-class" {
            class = "nixos";
            identity = "a";
            module = {
              x = 1;
            };
          })
          (fx.send "emit-class" {
            class = "packages";
            identity = "b";
            module = {
              y = 2;
            };
          })
          (fx.send "emit-class" {
            class = "nixos";
            identity = "c";
            module = {
              z = 3;
            };
          })
        ];
        result = fx.handle {
          handlers = handlers.classCollectorHandler;
          state = {
            classImports = _: { };
            currentScope = "__test";
            scopedClassImports = _: { };
          };
        } comp;
      in
      {
        expr = builtins.length (
          (builtins.foldl' (
            acc: sd:
            lib.zipAttrsWith (_: builtins.concatLists) [
              acc
              sd
            ]
          ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
        );
        expected = 2;
      }
    );

    # --- defer-include / drain-deferred handler tests ---

    # defer-include accumulates into deferredIncludes thunk chain.
    test-defer-include-accumulates = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        comp =
          fx.bind
            (fx.send "defer" {
              child = {
                name = "a";
                __fn = _: { };
                __args = {
                  host = false;
                };
              };
              requiredKeys = [ "host" ];
              requiredArgs = [ "host" ];
            })
            (
              _:
              fx.send "defer" {
                child = {
                  name = "b";
                  __fn = _: { };
                  __args = {
                    user = false;
                  };
                };
                requiredKeys = [ "user" ];
                requiredArgs = [ "user" ];
              }
            );
        result = fx.handle {
          handlers = handlers.deferHandler // {
            "resolve-complete" =
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
        expr = builtins.length ((result.state.scopedDeferredIncludes null).__test or [ ]);
        expected = 2;
      }
    );

    # drain-deferred returns satisfiable entries and keeps the rest.
    test-drain-deferred-partitions = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        deferredA = {
          child = {
            name = "needs-host";
          };
          requiredArgs = [ "host" ];
        };
        deferredB = {
          child = {
            name = "needs-user";
          };
          requiredArgs = [ "user" ];
        };
        comp = fx.send "drain" { host = { }; };
        result = fx.handle {
          handlers = handlers.drainHandler;
          state = {
            currentScope = "__test";
            scopedDeferredIncludes = _: {
              __test = [
                deferredA
                deferredB
              ];
            };
          };
        } comp;
        satisfiable = result.value;
        remaining = (result.state.scopedDeferredIncludes null).__test or [ ];
      in
      {
        expr = {
          satisfiedCount = builtins.length satisfiable;
          satisfiedName = (builtins.head satisfiable).child.name;
          remainingCount = builtins.length remaining;
          remainingName = (builtins.head remaining).child.name;
        };
        expected = {
          satisfiedCount = 1;
          satisfiedName = "needs-host";
          remainingCount = 1;
          remainingName = "needs-user";
        };
      }
    );

    # drain-deferred with empty context returns nothing.
    test-drain-deferred-empty-ctx = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        deferred = {
          child = {
            name = "needs-host";
          };
          requiredArgs = [ "host" ];
        };
        comp = fx.send "drain" { };
        result = fx.handle {
          handlers = handlers.drainHandler;
          state = {
            currentScope = "__test";
            scopedDeferredIncludes = _: {
              __test = [ deferred ];
            };
          };
        } comp;
      in
      {
        expr = {
          satisfiedCount = builtins.length result.value;
          remainingCount = builtins.length ((result.state.scopedDeferredIncludes null).__test or [ ]);
        };
        expected = {
          satisfiedCount = 0;
          remainingCount = 1;
        };
      }
    );

  };
}
