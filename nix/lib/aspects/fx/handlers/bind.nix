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
              entityCls = ((state.scopeEntityClass or (_: { })) null).${currentScope} or null;
            in
            (ctxs.${currentScope} or { }) // (if entityCls != null then { class = entityCls; } else { })
          else
            { };
        keysAfterStateFallback = builtins.filter (k: !(scopeCtx ? ${k})) keysToProbe;
        # Detect pipe arg references: if any required keys are pipe names,
        # unconditionally defer — pipe data is assembled post-pipeline.
        pipeRegistry = den.quirks or { };
        hasPipeArgs = builtins.any (k: pipeRegistry ? ${k}) requiredKeys;
        # Augment __scopeHandlers with ALL requested keys available in scope
        # context (both required and optional).  This ensures scope.provide
        # values (host, user, class) override pipeline-level defaults even
        # for optional args.
        allRequestedKeys = builtins.attrNames childArgs;
        scopeOverrideKeys = builtins.filter (
          k: !(childScopeHandlers ? ${k}) && scopeCtx ? ${k}
        ) allRequestedKeys;
        augmentedAspect =
          if scopeOverrideKeys != [ ] then
            let
              stateHandlers = den.lib.aspects.fx.handlers.constantHandler (
                builtins.listToAttrs (
                  map (k: {
                    name = k;
                    value = scopeCtx.${k};
                  }) scopeOverrideKeys
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
              inherit hasPipeArgs;
            }) (_: fx.pure { deferred = true; })
        );
        inherit state;
      };
  };
}
