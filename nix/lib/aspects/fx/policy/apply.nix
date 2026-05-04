# Apply policy effects to the pipeline via fx.send.
# Bridges classified policy results into handler messages.
{
  fx,
  identity,
}:
let
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
  policyEmitExcludes =
    effects:
    builtins.foldl' (
      acc: e:
      fx.bind acc (
        _:
        fx.send "register-constraint" {
          type = "exclude";
          scope = "subtree";
          identity = identity.key e.value;
          owner = "policy";
        }
      )
    ) (fx.pure null) effects;

  # Emit policy route, instantiate, and provide effects.
  policyEmitEffects =
    routeEffects: instantiateEffects: provideEffects:
    fx.bind
      (builtins.foldl' (
        acc: e: fx.bind acc (_: fx.send "register-route" e.value)
      ) (fx.pure null) routeEffects)
      (
        _:
        fx.bind
          (builtins.foldl' (
            acc: e: fx.bind acc (_: fx.send "register-instantiate" e.value)
          ) (fx.pure null) instantiateEffects)
          (
            _:
            builtins.foldl' (
              acc: e:
              fx.bind acc (
                _: fx.send "register-provide" (e.value // { __providePolicyName = e.__providePolicyName or null; })
              )
            ) (fx.pure null) provideEffects
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
