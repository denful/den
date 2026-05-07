# Apply policy effects to the pipeline via fx.send.
# Bridges classified policy results into handler messages.
{
  fx,
  identity,
}:
let
  # Sequentially send an effect for each item in a list.
  sendEach =
    effect: transform: effects:
    builtins.foldl' (acc: e: fx.bind acc (_: fx.send effect (transform e))) (fx.pure null) effects;

  # Emit policy include effects via existing handlers.
  # parentScopeHandlers: optional scope handlers to propagate through includes
  # (needed for late dispatch where scope.provide doesn't survive handler boundaries).
  policyEmitIncludes =
    effects:
    {
      parentScopeHandlers ? null,
    }:
    let
      len = builtins.length effects;
      go =
        idx: acc:
        if idx >= len then
          acc
        else
          let
            e = builtins.elemAt effects idx;
            policyName = e.__sourcePolicyName or null;
            # Append index when multiple includes share a policy name to prevent
            # dedup collisions in the class collector.
            suffix = if len > 1 then "[${toString idx}]" else "";
            child =
              if policyName != null && builtins.isAttrs e.value && !(e.value ? name) then
                e.value // { name = "<policy:${policyName}>${suffix}"; }
              else
                e.value;
          in
          go (idx + 1) (
            fx.bind acc (
              prev:
              fx.bind (fx.send "emit-include" {
                inherit child;
                idx = null;
                __parentScopeHandlers = parentScopeHandlers;
              }) (r: fx.pure (prev ++ r))
            )
          );
    in
    go 0 (fx.pure [ ]);

  # Emit policy exclude effects.
  policyEmitExcludes = sendEach "register-constraint" (e: {
    type = "exclude";
    scope = "subtree";
    identity = identity.key e.value;
    owner = "policy";
  });

  # Emit policy route, instantiate, and provide effects.
  policyEmitEffects =
    routeEffects: instantiateEffects: provideEffects:
    fx.bind (sendEach "register-route" (e: e.value) routeEffects) (
      _:
      fx.bind (sendEach "register-instantiate" (e: e.value) instantiateEffects) (
        _:
        sendEach "register-provide" (
          e: e.value // { __providePolicyName = e.__providePolicyName or null; }
        ) provideEffects
      )
    );

  # Emit pipe effects via register-pipe-effect handler.
  policyEmitPipeEffects = sendEach "register-pipe-effect" (
    e: e.value // { __pipePolicyName = e.__pipePolicyName or null; }
  );

  # Emit excludes, route/instantiate/provide/pipe effects, then run a continuation.
  emitPolicyEffectsThen =
    effects: cont:
    fx.bind (policyEmitExcludes effects.excludeEffects) (
      _:
      fx.bind (policyEmitEffects effects.routeEffects effects.instantiateEffects effects.provideEffects) (
        _: fx.bind (policyEmitPipeEffects (effects.pipeEffects or [ ])) (_: cont)
      )
    );

  # Emit new aspects as includes for already-seen contexts.
  mkSupplementalResolution =
    scopeHandlersForCtx: ctxNames: prevResults: newAspectValues:
    builtins.foldl' (
      sAcc: supAspect:
      fx.bind sAcc (
        sPrev:
        fx.bind (fx.send "emit-include" {
          child = supAspect;
          idx = null;
          __parentScopeHandlers = scopeHandlersForCtx;
          __parentCtxId = ctxNames;
        }) (_: fx.pure sPrev)
      )
    ) (fx.pure prevResults) newAspectValues;
in
{
  inherit
    policyEmitIncludes
    policyEmitExcludes
    policyEmitEffects
    emitPolicyEffectsThen
    mkSupplementalResolution
    ;
}
