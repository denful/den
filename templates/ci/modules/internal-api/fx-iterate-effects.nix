{
  denTest,
  lib,
  ...
}:
{
  flake.tests.fx-iterate-effects = {

    # record-fired updates firedPolicyNames with dispatch key.
    test-record-fired-updates-state = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;

        comp = fx.send "record-fired" {
          entityKind = "hosts";
          firedPolicies = {
            pol-a = true;
            pol-b = true;
          };
        };

        result = fx.handle {
          handlers = handlers.recordFiredHandler;
          state = {
            currentScope = "root";
            firedPolicyNames = _: { };
          };
        } comp;

        fired = result.state.firedPolicyNames null;
      in
      {
        expr = {
          hasKey = fired ? "hosts@root";
          policies = fired."hosts@root";
          resumed = result.value;
        };
        expected = {
          hasKey = true;
          policies = {
            pol-a = true;
            pol-b = true;
          };
          resumed = null;
        };
      }
    );

    # record-fired preserves existing entries.
    test-record-fired-preserves-existing = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;

        comp = fx.send "record-fired" {
          entityKind = "users";
          firedPolicies = {
            pol-c = true;
          };
        };

        result = fx.handle {
          handlers = handlers.recordFiredHandler;
          state = {
            currentScope = "child";
            firedPolicyNames = _: {
              "hosts@root" = {
                pol-a = true;
              };
            };
          };
        } comp;

        fired = result.state.firedPolicyNames null;
      in
      {
        expr = {
          existingPreserved = fired ? "hosts@root";
          newAdded = fired ? "users@child";
        };
        expected = {
          existingPreserved = true;
          newAdded = true;
        };
      }
    );

    # widen-context updates scopeContexts with merged enrichment.
    test-widen-context-updates-state = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;

        comp = fx.send "widen-context" {
          currentCtx = {
            host = "igloo";
          };
          enrichment = {
            user = "tux";
          };
        };

        result = fx.handle {
          handlers = handlers.widenContextHandler;
          state = {
            currentScope = "root";
            scopeContexts = _: { };
          };
        } comp;

        contexts = result.state.scopeContexts null;
      in
      {
        expr = {
          resumed = result.value;
          ctx = contexts."root";
        };
        expected = {
          resumed = null;
          ctx = {
            host = "igloo";
            user = "tux";
          };
        };
      }
    );

    # widen-context preserves existing scope contexts.
    test-widen-context-preserves-other-scopes = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;

        comp = fx.send "widen-context" {
          currentCtx = {
            host = "igloo";
          };
          enrichment = {
            user = "tux";
          };
        };

        result = fx.handle {
          handlers = handlers.widenContextHandler;
          state = {
            currentScope = "child";
            scopeContexts = _: {
              root = {
                host = "glacier";
              };
            };
          };
        } comp;

        contexts = result.state.scopeContexts null;
      in
      {
        expr = {
          rootPreserved = contexts."root";
          childAdded = contexts."child";
        };
        expected = {
          rootPreserved = {
            host = "glacier";
          };
          childAdded = {
            host = "igloo";
            user = "tux";
          };
        };
      }
    );

    # emit-policy-effects with empty effects runs without error.
    test-emit-policy-effects-empty = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;

        emptyEffects = {
          schemaEffects = [ ];
          includeEffects = [ ];
          excludeEffects = [ ];
          routeEffects = [ ];
          instantiateEffects = [ ];
          provideEffects = [ ];
        };

        # Mock processSchemaResolves — should not be called with empty schemaEffects.
        mockProcessSchemaResolves =
          _: _: _: _:
          throw "should not be called";

        emitHandler = handlers.mkEmitPolicyEffectsHandler mockProcessSchemaResolves;

        comp = fx.send "emit-policy-effects" {
          effects = emptyEffects;
          entityKind = "hosts";
          enrichedCtx = {
            host = "igloo";
          };
        };

        # The handler returns an fx computation as resume, so we need a second
        # handle layer to catch the effects it emits (register-constraint, etc.).
        # With empty effects it emits nothing, so we just need stubs.
        inner = fx.handle {
          handlers = emitHandler;
          state = { };
        } comp;
      in
      {
        expr = {
          # resume is an fx computation; run it to get final value
          value = inner.value;
        };
        expected = {
          # policyEmitIncludes [] returns fx.pure [] which resolves to []
          value = [ ];
        };
      }
    );

    # emit-policy-effects with include effects emits them.
    test-emit-policy-effects-with-includes = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;

        effects = {
          schemaEffects = [ ];
          includeEffects = [
            {
              value = {
                name = "test-module";
              };
            }
          ];
          excludeEffects = [ ];
          routeEffects = [ ];
          instantiateEffects = [ ];
          provideEffects = [ ];
        };

        mockProcessSchemaResolves =
          _: _: _: _:
          throw "should not be called";
        emitHandler = handlers.mkEmitPolicyEffectsHandler mockProcessSchemaResolves;

        comp = fx.send "emit-policy-effects" {
          inherit effects;
          entityKind = "hosts";
          enrichedCtx = { };
        };

        # The resume is an fx computation that sends emit-include.
        # All effect sends happen within the same handler context.
        result = fx.handle {
          handlers = emitHandler // {
            "emit-include" =
              { param, state }:
              {
                resume = [ param.child ];
                inherit state;
              };
          };
          state = { };
        } comp;
      in
      {
        expr = {
          resultLength = builtins.length result.value;
          firstName = (builtins.head result.value).name;
        };
        expected = {
          resultLength = 1;
          firstName = "test-module";
        };
      }
    );

  };
}
