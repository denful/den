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
        mockMkDispatch = directPolicies: aspectPolicies: firedPolicies: resolveCtx: {
          schemaEffects = [ ];
          includeEffects = [ ];
          excludeEffects = [ ];
          routeEffects = [ ];
          instantiateEffects = [ ];
          provideEffects = [ ];
          enrichment = { };
          firedNames = [ ];
          # Echo inputs for verification.
          __directCount = builtins.length (builtins.attrNames directPolicies);
          __resolveKind = resolveCtx.__entityKind or "none";
        };

        dispatchHandler = handlers.mkDispatchPoliciesHandler mockMkDispatch;

        comp = fx.send "dispatch-policies" {
          directPolicies = {
            pol-a = _: [ ];
            pol-b = _: [ ];
          };
          aspectPolicies = { };
          firedPolicies = { };
          resolveCtx = {
            __entityKind = "hosts";
          };
        };

        result = fx.handle {
          handlers = dispatchHandler;
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
            __directCount
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
          __directCount = 2;
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

        mockMkDispatch = _: _: _: _: {
          firedNames = [ ];
        };

        dispatchHandler = handlers.mkDispatchPoliciesHandler mockMkDispatch;

        comp = fx.send "dispatch-policies" {
          directPolicies = { };
          aspectPolicies = { };
          firedPolicies = { };
          resolveCtx = { };
        };

        initialState = {
          someField = "preserved";
          counter = 42;
        };

        result = fx.handle {
          handlers = dispatchHandler;
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
        inherit (den.lib.schemaUtil) schemaEntityKinds;

        classify = import ../../../../nix/lib/aspects/fx/policy/classify.nix {
          inherit lib schemaEntityKinds;
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
        testPolicy =
          { __entityKind, ... }:
          [
            {
              __policyEffect = "include";
              value = "some-module";
            }
          ];

        comp = fx.send "dispatch-policies" {
          directPolicies = {
            test-pol = testPolicy;
          };
          aspectPolicies = { };
          firedPolicies = { };
          resolveCtx = {
            __entityKind = "hosts";
          };
        };

        result = fx.handle {
          handlers = dispatchHandler;
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
