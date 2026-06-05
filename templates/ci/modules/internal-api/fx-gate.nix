{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-gate = {

    # Aspect with no constraints and no prior dedup passes cleanly.
    test-gate-pass-through = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        pipeline = den.lib.aspects.fx.pipeline;
        aspect = {
          name = "my-aspect";
          meta.provider = [ ];
          includes = [ ];
        };
        comp = fx.send "gate" {
          aspect = aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
        };
        result = fx.handle {
          handlers =
            handlers.gateHandler
            // handlers.checkDedupHandler
            // handlers.constraintRegistryHandler
            // den.lib.aspects.fx.identity.collectPathsHandler;
          state = pipeline.defaultState;
        } comp;
      in
      {
        expr = result.value;
        expected = {
          passed = true;
        };
      }
    );

    # Pre-seeded dedup blocks second send of the same aspect.
    test-gate-blocks-duplicate = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        pipeline = den.lib.aspects.fx.pipeline;
        aspect = {
          name = "dup-aspect";
          meta.provider = [ ];
          includes = [ ];
        };
        # Send gate twice — second should be blocked by dedup.
        comp =
          fx.bind
            (fx.send "gate" {
              aspect = aspect;
              identity = den.lib.aspects.fx.identity.key aspect;
            })
            (
              _:
              fx.send "gate" {
                aspect = aspect;
                identity = den.lib.aspects.fx.identity.key aspect;
              }
            );
        result = fx.handle {
          handlers =
            handlers.gateHandler
            // handlers.checkDedupHandler
            // handlers.constraintRegistryHandler
            // den.lib.aspects.fx.identity.collectPathsHandler;
          state = pipeline.defaultState;
        } comp;
      in
      {
        expr = result.value;
        expected = {
          blocked = true;
          result = [ ];
        };
      }
    );

    # Registered exclude constraint blocks the aspect.
    test-gate-blocks-constraint-exclude = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        pipeline = den.lib.aspects.fx.pipeline;
        aspect = {
          name = "excluded-aspect";
          meta.provider = [ ];
          includes = [ ];
        };
        nodeIdentity = den.lib.aspects.fx.identity.key aspect;
        # Register an exclude constraint, then gate the aspect.
        comp =
          fx.bind
            (fx.send "register-constraint" {
              type = "exclude";
              identity = nodeIdentity;
              owner = "test-owner";
            })
            (
              _:
              fx.send "gate" {
                inherit aspect;
                identity = nodeIdentity;
              }
            );
        result = fx.handle {
          handlers =
            handlers.gateHandler
            // handlers.checkDedupHandler
            // handlers.constraintRegistryHandler
            // handlers.includeHandler
            // den.lib.aspects.fx.identity.collectPathsHandler;
          state = pipeline.defaultState;
        } comp;
      in
      {
        expr = {
          blocked = result.value.blocked;
          tombstoneCount = builtins.length result.value.result;
          tombstoneName = (builtins.head result.value.result).name;
          isExcluded = (builtins.head result.value.result).meta.excluded;
        };
        expected = {
          blocked = true;
          tombstoneCount = 1;
          tombstoneName = "~excluded-aspect";
          isExcluded = true;
        };
      }
    );

    # Registered substitute constraint replaces the aspect.
    test-gate-blocks-constraint-substitute = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        pipeline = den.lib.aspects.fx.pipeline;
        aspect = {
          name = "original-aspect";
          meta.provider = [ ];
          includes = [ ];
        };
        replacement = {
          name = "replacement-aspect";
          meta.provider = [ ];
          includes = [ ];
        };
        nodeIdentity = den.lib.aspects.fx.identity.key aspect;
        # Register a substitute constraint, then gate the aspect.
        comp =
          fx.bind
            (fx.send "register-constraint" {
              type = "substitute";
              identity = nodeIdentity;
              owner = "test-owner";
              getReplacement = _: replacement;
            })
            (
              _:
              fx.send "gate" {
                inherit aspect;
                identity = nodeIdentity;
              }
            );
        result = fx.handle {
          handlers =
            handlers.gateHandler
            // handlers.checkDedupHandler
            // handlers.constraintRegistryHandler
            // handlers.includeHandler
            // handlers.chainHandler
            // handlers.resolveHandler
            // handlers.compileHandler
            // handlers.compileStaticHandler
            // handlers.compileParametricHandler
            // handlers.compileConditionalHandler
            // handlers.compileForwardHandler
            // handlers.bindHandler
            // handlers.deferHandler
            // handlers.drainHandler
            // handlers.classifyHandler
            // handlers.emitClassesHandler
            // handlers.resolveChildrenHandler
            // den.lib.aspects.fx.identity.pathSetHandler
            // den.lib.aspects.fx.identity.collectPathsHandler;
          state = pipeline.defaultState;
        } comp;
      in
      {
        expr = {
          blocked = result.value.blocked;
          resultCount = builtins.length result.value.result;
          tombstoneName = (builtins.elemAt result.value.result 0).name;
          hasReplacedBy = (builtins.elemAt result.value.result 0).meta ? replacedBy;
        };
        expected = {
          blocked = true;
          resultCount = 2;
          tombstoneName = "~original-aspect";
          hasReplacedBy = true;
        };
      }
    );

  };
}
