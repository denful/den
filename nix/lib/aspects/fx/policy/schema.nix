# Schema resolve processing — entity scope transitions and fan-out.
{
  lib,
  fx,
  den,
  identity,
  constantHandler,
  mkScopeId,
  schemaEntityKinds,
  classifyPolicyResult,
  extractTaggedEffects,
  dispatchAspect,
  emitPolicyEffectsThen,
  policyEmitIncludes,
  mkSupplementalResolution,
  decomposeSchemaEffect,
}:
let
  # Determine target entity kind from a schema effect.
  resolveTargetKind =
    entityKind: schemaEffect:
    let
      keys = builtins.attrNames schemaEffect.schema.value;
    in
    if schemaEffect.schema.__targetKind or null != null then
      schemaEffect.schema.__targetKind
    else
      lib.findFirst (k: builtins.elem k schemaEntityKinds) (
        if keys != [ ] then builtins.head keys else entityKind
      ) keys;

  # Resolve entity class from schema bindings for scope handler override.
  resolveEntityClass =
    targetKind: resolveBindings:
    let
      entity = resolveBindings.${targetKind} or null;
      classes = if entity != null then entity.classes or null else null;
    in
    if classes != null && classes != [ ] then builtins.head classes else null;

  # Process a single schema resolve effect within the fold.
  processSingleResolve =
    entityKind: enrichedCtx: includeAspects: isFanOut: prevResults: schemaEffect:
    let
      inherit (decomposeSchemaEffect entityKind enrichedCtx schemaEffect)
        targetKind resolveBindings scopedCtx entityClass;
      ctxNames = mkScopeId scopedCtx;
      ctxKey = if isFanOut then "${targetKind}/{${ctxNames}}" else targetKind;
      scopeHandlersForCtx = constantHandler (
        scopedCtx // lib.optionalAttrs (entityClass != null) { class = entityClass; }
      );
      policyIncludes = schemaEffect.__policyIncludes or [ ];
      resolveIncludes = schemaEffect.schema.includes or [ ];
      policyAspectPaths = map identity.key (includeAspects ++ policyIncludes ++ resolveIncludes);
    in
    fx.bind
      (fx.send "ctx-seen" {
        key = ctxKey;
        aspects = policyAspectPaths;
        aspectValues = includeAspects;
      })
      (
        { isFirst, newAspectValues }:
        if isFirst then
          fx.send "resolve-schema-entity" {
            inherit
              targetKind
              scopedCtx
              entityClass
              includeAspects
              policyIncludes
              resolveIncludes
              ctxNames
              prevResults
              ;
          }
        else if newAspectValues != [ ] then
          mkSupplementalResolution scopeHandlersForCtx ctxNames prevResults newAspectValues
        else
          fx.pure prevResults
      );

  # Emit late policy effects into a single sibling scope.
  emitLateForSibling =
    parentScope: allAspectPolicies: firedPerScope: sib:
    let
      dispatchKey = "${sib.targetKind}@${sib.scopeId}";
      alreadyFired = firedPerScope.${dispatchKey} or { };
      latePolicies = lib.filterAttrs (name: _: !(alreadyFired ? ${name})) allAspectPolicies;
      resolveCtx = sib.scopedCtx // { __entityKind = sib.targetKind; };
      lateResults = dispatchAspect latePolicies alreadyFired resolveCtx;
      late = extractTaggedEffects (map classifyPolicyResult lateResults);
      hasLateEffects =
        late.includeEffects != [ ]
        || late.routeEffects != [ ]
        || late.instantiateEffects != [ ]
        || late.provideEffects != [ ]
        || late.excludeEffects != [ ];
      scopeHandlersForCtx = constantHandler (
        sib.scopedCtx // lib.optionalAttrs (sib.entityClass != null) { class = sib.entityClass; }
      );
    in
    if latePolicies == { } || !hasLateEffects then
      fx.pure null
    else
      fx.bind (fx.effects.state.modify (st: st // { currentScope = sib.scopeId; })) (
        _:
        fx.bind
          (fx.effects.scope.provide scopeHandlersForCtx (
            emitPolicyEffectsThen late (policyEmitIncludes late.includeEffects)
          ))
          (_: fx.effects.state.modify (st: st // { currentScope = parentScope; }))
      );

  # Post-resolve pass: re-dispatch aspect policies registered by later siblings.
  lateDispatchPass =
    siblingMetas:
    fx.bind (fx.effects.state.modify (st: st // { inLateDispatch = true; })) (
      _:
      fx.bind fx.effects.state.get (
        state:
        let
          allAspectPolicies = state.flatAspectPolicies or { };
          firedPerScope = (state.firedPolicyNames or (_: { })) null;
          parentScope = state.currentScope;
        in
        builtins.foldl' (
          acc: sib:
          fx.bind acc (_: emitLateForSibling parentScope allAspectPolicies firedPerScope sib)
        ) (fx.pure null) siblingMetas
      )
    );

  # Process schema resolve effects with fan-out and late-dispatch.
  processSchemaResolves =
    entityKind: includeAspects: schemaEffects: enrichedCtx:
    processSchemaResolvesInner false entityKind includeAspects schemaEffects enrichedCtx;

  processSchemaResolvesInner =
    isLatePass: entityKind: includeAspects: schemaEffects: enrichedCtx:
    let
      isFanOut = builtins.length schemaEffects > 1;
      mainFold = builtins.foldl' (
        acc: schemaEffect:
        fx.bind acc (
          prevResults:
          processSingleResolve entityKind enrichedCtx includeAspects isFanOut prevResults schemaEffect
        )
      ) (fx.pure [ ]) schemaEffects;
    in
    if !isFanOut || isLatePass then
      mainFold
    else
      fx.bind fx.effects.state.get (
        preState:
        if (preState.inLateDispatch or false) then
          mainFold
        else
          fx.bind mainFold (
            allResults:
            let
              siblingMetas = map (
                schemaEffect:
                let
                  d = decomposeSchemaEffect entityKind enrichedCtx schemaEffect;
                in
                {
                  inherit (d) targetKind scopedCtx entityClass;
                  scopeId = mkScopeId d.scopedCtx;
                }
              ) schemaEffects;
            in
            fx.bind (lateDispatchPass siblingMetas) (_: fx.pure allResults)
          )
      );
in
{
  inherit
    resolveTargetKind
    resolveEntityClass
    processSingleResolve
    lateDispatchPass
    processSchemaResolves
    ;
}
