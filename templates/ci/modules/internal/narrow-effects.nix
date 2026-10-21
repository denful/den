# Tests for narrow-effects decomposition: resolve-aspect, resolve-conditional,
# check-dedup, resolve-parametric. Each test drives the handler(s) directly.
{ denTest, ... }:
let
  # Minimal handler set covering the narrow-effect handlers under test.
  # Uses a simple emit-class accumulator (avoids pipeline state shape coupling).
  mkHandlers =
    {
      den,
      extraHandlers ? { },
    }:
    let
      fx = den.lib.fx;
      handlers = den.lib.aspects.fx.handlers;
    in
    handlers.includeHandler
    // handlers.checkDedupHandler
    // handlers.constraintRegistryHandler
    // handlers.chainHandler
    // den.lib.aspects.fx.identity.collectPathsHandler
    // handlers.resolveHandler
    // handlers.compileHandler
    // handlers.gateHandler
    // handlers.compileStaticHandler
    // handlers.compileParametricHandler
    // handlers.compileConditionalHandler
    // handlers.deferConditionalHandler
    // handlers.drainConditionalsHandler
    // handlers.compileForwardHandler
    // handlers.bindHandler
    // handlers.deferHandler
    // handlers.drainHandler
    // handlers.classifyHandler
    // handlers.emitClassesHandler
    // handlers.resolveChildrenHandler
    // {
      "emit-class" =
        { param, state }:
        {
          resume = null;
          state = state // {
            classes = (state.classes or [ ]) ++ [ param ];
          };
        };
      "resolve-complete" =
        { param, state }:
        {
          resume = param;
          inherit state;
        };
      "check-constraint" =
        { param, state }:
        {
          resume = {
            action = "keep";
          };
          inherit state;
        };
    }
    // extraHandlers
    // fx.effects.state.handler;

  defaultState = {
    currentScope = "__test";
    rootScopeId = "__test";
    scopedIncludesChain = _: { };
    scopedConstraintRegistry = _: { };
    paths = [ ];
  };
in
{
  flake.tests.narrow-effects = {

    # resolve-aspect: static aspect emits its class and resolves to itself.
    test-resolve-aspect-static = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "myAspect";
          meta = { };
          nixos.services.nginx.enable = true;
          includes = [ ];
        };
        comp = fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
        result = fx.handle {
          handlers = mkHandlers { inherit den; };
          state = defaultState;
        } comp;
        emittedClasses = result.state.classes or [ ];
      in
      {
        expr = {
          resolvedName = (builtins.head result.value).name;
          classCount = builtins.length emittedClasses;
          className = (builtins.head emittedClasses).class;
        };
        expected = {
          resolvedName = "myAspect";
          classCount = 1;
          className = "nixos";
        };
      }
    );

    # resolve-conditional: guard passes — child aspect resolves, its class emits.
    test-resolve-conditional-guard-pass = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        child = {
          name = "feature";
          meta = { };
          nixos.networking.hostName = "cond-host";
          includes = [ ];
        };
        guarded = den.lib.aspects.fx.includes.includeIf (_: true) [ child ];
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
          handlers = mkHandlers { inherit den; };
          state = defaultState;
        } comp;
      in
      {
        expr = {
          resolvedChildName = (builtins.head (builtins.head result.value).includes).name;
          classCount = builtins.length (result.state.classes or [ ]);
        };
        expected = {
          resolvedChildName = "feature";
          classCount = 1;
        };
      }
    );

    # resolve-conditional: guard fails — deferred, then drained as tombstone
    # at resolve-children boundary. No classes emitted.
    test-resolve-conditional-guard-fail = denTest (
      { den, lib, ... }:
      let
        fx = den.lib.fx;
        child = {
          name = "feature";
          meta = { };
          nixos.networking.hostName = "cond-host";
          includes = [ ];
        };
        guarded = den.lib.aspects.fx.includes.includeIf (_: false) [ child ];
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
          handlers = mkHandlers { inherit den; };
          state = defaultState;
        } comp;
        children = (builtins.head result.value).includes;
        tombstone = lib.findFirst (c: c.meta.excluded or false) null children;
      in
      {
        expr = {
          classCount = builtins.length (result.state.classes or [ ]);
          tombstoneFound = tombstone != null;
          tombstoneGuardFailed = if tombstone != null then tombstone.meta.guardFailed or false else false;
        };
        expected = {
          classCount = 0;
          tombstoneFound = true;
          tombstoneGuardFailed = true;
        };
      }
    );

    # check-dedup: same named include twice — second is a duplicate.
    test-check-dedup-second-is-duplicate = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        inherit (den.lib.aspects.fx.handlers) checkDedupHandler;

        namedChild = {
          name = "my-aspect";
          meta = { };
          includes = [ ];
        };

        comp = fx.bind (fx.send "check-dedup" namedChild) (
          first: fx.bind (fx.send "check-dedup" namedChild) (second: fx.pure { inherit first second; })
        );

        result = fx.handle {
          handlers = checkDedupHandler;
          state = {
            currentScope = "root";
          };
        } comp;
      in
      {
        expr = {
          firstIsDuplicate = result.value.first.isDuplicate;
          secondIsDuplicate = result.value.second.isDuplicate;
          dedupKeySet = result.value.first.dedupKey != null;
        };
        expected = {
          firstIsDuplicate = false;
          secondIsDuplicate = true;
          dedupKeySet = true;
        };
      }
    );

    # check-dedup: anonymous (<name>) — never deduped regardless of repetition.
    test-check-dedup-anon-never-deduped = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        inherit (den.lib.aspects.fx.handlers) checkDedupHandler;

        anonChild = {
          name = "<anon>";
          meta = { };
          includes = [ ];
        };

        comp = fx.bind (fx.send "check-dedup" anonChild) (
          first: fx.bind (fx.send "check-dedup" anonChild) (second: fx.pure { inherit first second; })
        );

        result = fx.handle {
          handlers = checkDedupHandler;
          state = {
            currentScope = "root";
          };
        } comp;
      in
      {
        expr = {
          firstIsDuplicate = result.value.first.isDuplicate;
          secondIsDuplicate = result.value.second.isDuplicate;
          dedupKeyNull = result.value.first.dedupKey == null;
        };
        expected = {
          firstIsDuplicate = false;
          secondIsDuplicate = false;
          dedupKeyNull = true;
        };
      }
    );

    # resolve-parametric: parametric child resolves when its required arg handler is present.
    test-resolve-parametric-args-available = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        parametricChild = {
          name = "web";
          meta = { };
          __fn =
            { host }:
            {
              nixos.networking.hostName = host;
              includes = [ ];
            };
          __args = {
            host = false;
          };
        };
        parent = {
          name = "root";
          meta = { };
          includes = [ parametricChild ];
        };
        comp = fx.send "resolve" {
          aspect = parent;
          identity = den.lib.aspects.fx.identity.key parent;
          ctx = { };
        };
        result = fx.handle {
          handlers = mkHandlers {
            inherit den;
            extraHandlers = {
              host =
                { param, state }:
                {
                  resume = "igloo";
                  inherit state;
                };
            };
          };
          state = defaultState;
        } comp;
        resolvedChild = builtins.head (builtins.head result.value).includes;
      in
      {
        expr = {
          resolvedChildName = resolvedChild.name;
          classCount = builtins.length (result.state.classes or [ ]);
          emittedClass = (builtins.head (result.state.classes or [ { class = "none"; } ])).class;
        };
        expected = {
          resolvedChildName = "web";
          classCount = 1;
          emittedClass = "nixos";
        };
      }
    );

  };
}
