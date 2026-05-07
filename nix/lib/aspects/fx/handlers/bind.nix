# Handles: bind
# Probes scope handlers for required args, calls compileFn or defers.
{
  den,
  ...
}:
let
  inherit (den.lib) fx;
in
{
  bindHandler = {
    "bind" =
      { param, state }:
      let
        inherit (param) aspect compileFn;
        childArgs = aspect.__args or { };
        childScopeHandlers = aspect.__scopeHandlers or { };
        requiredKeys = builtins.filter (k: !childArgs.${k}) (builtins.attrNames childArgs);
        keysToProbe = builtins.filter (k: !(childScopeHandlers ? ${k})) requiredKeys;
        # Fallback: check current scope's context from pipeline state.
        # scope.provide doesn't survive handler boundaries, but the scope
        # context in state always reflects what's available at the current scope.
        # Only use at non-root scopes — root scope handlers work via the pipeline.
        currentScope = state.currentScope or null;
        rootScopeId = state.rootScopeId or null;
        isChildScope = currentScope != null && rootScopeId != null && currentScope != rootScopeId;
        scopeCtx =
          if isChildScope then
            let
              ctxs = (state.scopeContexts or (_: { })) null;
            in
            ctxs.${state.currentScope} or { }
          else
            { };
        keysAfterStateFallback = builtins.filter (k: !(scopeCtx ? ${k})) keysToProbe;
        # If state fallback satisfies all keys, merge scope handlers into aspect
        # so compileFn receives them for parametric binding.
        augmentedAspect =
          if keysAfterStateFallback != keysToProbe then
            let
              stateProvidedKeys = builtins.filter (k: scopeCtx ? ${k}) keysToProbe;
              stateHandlers = den.lib.aspects.fx.handlers.constantHandler (
                builtins.listToAttrs (
                  map (k: {
                    name = k;
                    value = scopeCtx.${k};
                  }) stateProvidedKeys
                )
              );
            in
            aspect
            // {
              __scopeHandlers = childScopeHandlers // stateHandlers;
            }
          else
            aspect;
        probeArgs =
          keys:
          if keys == [ ] then
            fx.pure true
          else
            let
              key = builtins.head keys;
              rest = builtins.tail keys;
            in
            fx.bind (fx.effects.hasHandler key) (
              isAvailable: if isAvailable then probeArgs rest else fx.pure false
            );
      in
      {
        resume = fx.bind (probeArgs keysAfterStateFallback) (
          allAvailable:
          if allAvailable then
            fx.bind (compileFn augmentedAspect) (result: fx.pure { value = result; })
          else
            fx.bind (fx.send "defer" {
              child = aspect;
              inherit requiredKeys;
              requiredArgs = keysAfterStateFallback;
            }) (_: fx.pure { deferred = true; })
        );
        inherit state;
      };
  };
}
