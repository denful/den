# Effect handler: resolve-children
# Chain-push → policies → includes → entity policies → chain-pop → resolve-complete.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx.aspect) ctxFromHandlers;

  inherit (import ../aspect { inherit lib den; } { inherit ctxFromHandlers; })
    emitIncludes
    emitAspectPolicies
    registerConstraints
    ;

  policyMod = import ../policy { inherit lib den; } {
    inherit ctxFromHandlers;
  };
  inherit (policyMod) installPolicies dispatchPoliciesHandler emitPolicyEffectsHandler;

  chainWrap =
    nodeIdentity: isMeaningful: comp:
    if isMeaningful then
      fx.bind (fx.send "chain-push" { identity = nodeIdentity; }) (
        _: fx.bind comp (result: fx.bind (fx.send "chain-pop" null) (_: fx.pure result))
      )
    else
      comp;

  resolveChildSequence =
    aspect:
    let
      emitCtx = {
        __parentScopeHandlers = aspect.__scopeHandlers or null;
        __parentCtxId = aspect.__ctxId or null;
      };
    in
    fx.bind (emitAspectPolicies aspect) (
      selfProvResults:
      fx.bind (emitIncludes emitCtx (aspect.includes or [ ])) (
        includeResults:
        if !(aspect ? __entityKind) then
          fx.pure (selfProvResults ++ includeResults)
        else
          fx.bind (installPolicies aspect) (
            policyResults: fx.pure (selfProvResults ++ includeResults ++ policyResults)
          )
      )
    );
in
{
  inherit dispatchPoliciesHandler emitPolicyEffectsHandler;
  resolveChildrenHandler = {
    "resolve-children" =
      { param, state }:
      let
        aspect = param.aspect;
        isMeaningful = param.isMeaningful;
        chainIdentity = param.chainIdentity;
      in
      {
        resume =
          let
            # Only drain deferred conditionals at entity-level aspects or
            # root scope aspects. Draining inside nested aspects is premature
            # — parent siblings haven't resolved yet.
            isEntityRoot = aspect ? __entityKind;
            maybeDrain =
              allChildren:
              fx.bind (fx.effects.hasHandler "drain-conditionals") (
                hasDrain:
                if !hasDrain then
                  fx.pure allChildren
                else if isEntityRoot then
                  fx.bind (fx.send "drain-conditionals" null) (results: fx.pure (allChildren ++ results))
                else
                  fx.bind fx.effects.state.get (
                    st:
                    if st.currentScope == (st.rootScopeId or null) then
                      fx.bind (fx.send "drain-conditionals" null) (results: fx.pure (allChildren ++ results))
                    else
                      fx.pure allChildren
                  )
              );
          in
          fx.bind (chainWrap chainIdentity isMeaningful (resolveChildSequence aspect)) (
            allChildren:
            fx.bind (maybeDrain allChildren) (
              finalChildren:
              let
                resolved = aspect // {
                  includes = finalChildren;
                };
              in
              fx.bind (fx.send "resolve-complete" resolved) (_: fx.pure resolved)
            )
          );
        inherit state;
      };
  };
}
