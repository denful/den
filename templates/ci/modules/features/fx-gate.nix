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

  };
}
