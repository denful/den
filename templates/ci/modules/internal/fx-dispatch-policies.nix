{
  denTest,
  lib,
  ...
}:
{
  flake.tests.fx-dispatch-policies = {

    # mkDispatchPoliciesHandler wraps mkDispatch, resumes its result, passes state through.
    test-dispatch-policies-resumes-result = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;

        # Mock mkDispatch: just return a tagged result so we can verify
        # the handler passes args correctly and resumes the return value.
        mockMkDispatch = aspectPolicies: firedPolicies: resolveCtx: {
          schemaEffects = [ ];
          includeEffects = [ ];
          excludeEffects = [ ];
          routeEffects = [ ];
          instantiateEffects = [ ];
          provideEffects = [ ];
          enrichment = { };
          firedNames = [ ];
          # Echo inputs for verification.
          __aspectCount = builtins.length (builtins.attrNames aspectPolicies);
          __resolveKind = resolveCtx.__entityKind or "none";
        };

        dispatchHandler = handlers.mkDispatchPoliciesHandler mockMkDispatch;

        comp = fx.send "dispatch-policies" {
          aspectPolicies = {
            pol-a = {
              __isPolicy = true;
              name = "pol-a";
              fn = _: [ ];
            };
            pol-b = {
              __isPolicy = true;
              name = "pol-b";
              fn = _: [ ];
            };
          };
          firedPolicies = { };
          resolveCtx = {
            __entityKind = "hosts";
          };
        };

        result = fx.handle {
          handlers = dispatchHandler // handlers.constraintRegistryHandler;
          state = { };
        } comp;
      in
      {
        expr = {
          inherit (result.value)
            schemaEffects
            includeEffects
            excludeEffects
            routeEffects
            instantiateEffects
            provideEffects
            enrichment
            firedNames
            __aspectCount
            __resolveKind
            ;
        };
        expected = {
          schemaEffects = [ ];
          includeEffects = [ ];
          excludeEffects = [ ];
          routeEffects = [ ];
          instantiateEffects = [ ];
          provideEffects = [ ];
          enrichment = { };
          firedNames = [ ];
          __aspectCount = 2;
          __resolveKind = "hosts";
        };
      }
    );

    # State is passed through unchanged (stateless handler).
    test-dispatch-policies-preserves-state = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;

        mockMkDispatch = _: _: _: {
          firedNames = [ ];
        };

        dispatchHandler = handlers.mkDispatchPoliciesHandler mockMkDispatch;

        comp = fx.send "dispatch-policies" {
          aspectPolicies = { };
          firedPolicies = { };
          resolveCtx = { };
        };

        initialState = {
          someField = "preserved";
          counter = 42;
        };

        result = fx.handle {
          handlers = dispatchHandler // handlers.constraintRegistryHandler;
          state = initialState;
        } comp;
      in
      {
        expr = result.state;
        expected = initialState;
      }
    );

    # Integration: real mkDispatch with a policy that fires.
    test-dispatch-policies-real-dispatch = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        inherit (den.lib.synthesizePolicies) resolveArgsSatisfied;
        inherit (den.lib.schemaUtil) schemaEntityKinds schemaEntityKindsSet;

        classify = import ../../../../nix/lib/aspects/fx/policy/classify.nix {
          inherit lib schemaEntityKinds schemaEntityKindsSet;
        };
        dispatch = import ../../../../nix/lib/aspects/fx/policy/dispatch.nix {
          inherit lib resolveArgsSatisfied;
          inherit (classify)
            classifyPolicyResult
            extractTaggedEffects
            hasEffects
            ;
        };
        inherit (dispatch) mkDispatch;

        dispatchHandler = handlers.mkDispatchPoliciesHandler mkDispatch;

        # A policy that emits an include effect.
        testPolicy = {
          __isPolicy = true;
          name = "test-pol";
          fn =
            { __entityKind, ... }:
            [
              {
                __policyEffect = "include";
                value = "some-module";
              }
            ];
        };

        comp = fx.send "dispatch-policies" {
          aspectPolicies = {
            test-pol = testPolicy;
          };
          firedPolicies = { };
          resolveCtx = {
            __entityKind = "hosts";
          };
        };

        result = fx.handle {
          handlers = dispatchHandler // handlers.constraintRegistryHandler;
          state = { };
        } comp;
      in
      {
        expr = {
          includeCount = builtins.length result.value.includeEffects;
          firedNames = result.value.firedNames;
          hasEnrichment = result.value.enrichment != { };
        };
        expected = {
          includeCount = 1;
          firedNames = [ "test-pol" ];
          hasEnrichment = false;
        };
      }
    );

  };
}
