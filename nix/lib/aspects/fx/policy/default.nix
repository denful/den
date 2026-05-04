# Policy dispatch subsystem — entry point.
# Runs user-defined policies, classifies effects, iterates to fixed-point.
{
  lib,
  den,
  ...
}:
{
  aspectToEffect,
  ctxFromHandlers,
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx.handlers) constantHandler;
  inherit (den.lib.synthesizePolicies) resolveArgsSatisfied;
  inherit (den.lib.aspects.fx.pipeline) mkScopeId;
  inherit (den.lib.aspects.fx) identity;
  inherit (den.lib.schemaUtil) schemaEntityKinds;

  classify = import ./classify.nix { inherit lib schemaEntityKinds; };
  inherit (classify) classifyPolicyResult hasEffects extractTaggedEffects;

  dispatch = import ./dispatch.nix {
    inherit lib resolveArgsSatisfied classifyPolicyResult extractTaggedEffects hasEffects;
  };
  inherit (dispatch) dispatchAspect mkDispatch;

  apply = import ./apply.nix { inherit fx identity; };
  inherit (apply)
    policyEmitIncludes
    policyEmitExcludes
    policyEmitEffects
    emitPolicyEffectsThen
    mkSupplementalResolution
    ;

  # Decompose a schema effect into its target kind, bindings, scoped ctx, and class.
  decomposeSchemaEffect =
    entityKind: enrichedCtx: schemaEffect:
    let
      targetKind = schema.resolveTargetKind entityKind schemaEffect;
      resolveBindings = schemaEffect.schema.value;
      scopedCtx = enrichedCtx // resolveBindings;
      entityClass = schema.resolveEntityClass targetKind resolveBindings;
    in
    {
      inherit targetKind resolveBindings scopedCtx entityClass;
    };

  schema = import ./schema.nix {
    inherit
      lib
      fx
      den
      identity
      constantHandler
      mkScopeId
      schemaEntityKinds
      classifyPolicyResult
      extractTaggedEffects
      dispatchAspect
      emitPolicyEffectsThen
      policyEmitIncludes
      mkSupplementalResolution
      decomposeSchemaEffect
      ;
  };
  inherit (schema) processSchemaResolves;

  iterateMod = import ./iterate.nix {
    inherit
      lib
      fx
      constantHandler
      aspectToEffect
      mkDispatch
      emitPolicyEffectsThen
      policyEmitIncludes
      processSchemaResolves
      ;
  };
  inherit (iterateMod) emptyAcc iterate;

  # Entry point: read state, check dedup, call iterate.
  installPolicies =
    aspect:
    let
      entityKind = aspect.__entityKind;
      ctx = ctxFromHandlers (aspect.__scopeHandlers or { });
    in
    fx.bind fx.effects.state.get (
      state:
      let
        scope = state.currentScope;
        scopeCtx = if scope == null then { } else (state.scopeContexts null).${scope} or { };
        currentCtx = scopeCtx // ctx;
        dispatchKey = "${entityKind}@${scope}";
        alreadyDispatched = ((state.dispatchedPolicies or (_: { })) null) ? ${dispatchKey};
        globalPolicies = den.policies or { };
        schemaPolicies = (den.schema.${entityKind} or { }).policies or { };
        allDirectPolicies = globalPolicies // schemaPolicies;
        aspectPolicies = state.flatAspectPolicies or { };
        resolveCtx = currentCtx // {
          __entityKind = entityKind;
        };
      in
      if alreadyDispatched then
        fx.pure [ ]
      else
        fx.bind (fx.effects.state.modify (
          st:
          st
          // {
            dispatchedPolicies = _: ((st.dispatchedPolicies or (_: { })) null) // { ${dispatchKey} = true; };
          }
        )) (_: iterate allDirectPolicies aspectPolicies entityKind currentCtx 0 { } emptyAcc { } resolveCtx)
    );
in
{
  inherit installPolicies;
}
