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
  policyEmitIncludes =
    effects:
    builtins.foldl' (
      acc: e:
      fx.bind acc (
        prev:
        let
          policyName = e.__sourcePolicyName or null;
          child =
            if policyName != null && builtins.isAttrs e.value && !(e.value ? name) then
              e.value // { name = "<policy:${policyName}>"; }
            else
              e.value;
        in
        fx.bind (fx.send "emit-include" {
          inherit child;
          idx = null;
        }) (r: fx.pure (prev ++ r))
      )
    ) (fx.pure [ ]) effects;

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

  # Emit excludes, route/instantiate/provide effects, then run a continuation.
  emitPolicyEffectsThen =
    effects: cont:
    fx.bind (policyEmitExcludes effects.excludeEffects) (
      _:
      fx.bind (policyEmitEffects effects.routeEffects effects.instantiateEffects effects.provideEffects) (
        _: cont
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
