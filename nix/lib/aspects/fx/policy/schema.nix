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
}:
let
  schemaEntityKindsSet = lib.genAttrs schemaEntityKinds (_: true);

  # Determine target entity kind from a schema effect.
  resolveTargetKind =
    entityKind: schemaEffect:
    let
      keys = builtins.attrNames schemaEffect.schema.value;
    in
    if schemaEffect.schema.__targetKind or null != null then
      schemaEffect.schema.__targetKind
    else
      lib.findFirst (k: schemaEntityKindsSet ? ${k}) (
        if keys != [ ] then builtins.head keys else entityKind
      ) keys;

  # Resolve entity class from schema bindings for scope handler override.
  resolveEntityClass =
    targetKind: resolveBindings:
    let
      entity = resolveBindings.${targetKind} or null;
      classes = if entity != null then entity.classes or null else null;
    in
    if classes != null && classes != [ ] then
      builtins.head classes
    else
    # Fallback to singular `class` (hosts use class, users use classes).
    if entity != null then
      entity.class or null
    else
      null;

  # Decompose a schema effect into its target kind, bindings, scoped ctx, and class.
  decomposeSchemaEffect =
    entityKind: enrichedCtx: schemaEffect:
    let
      targetKind = resolveTargetKind entityKind schemaEffect;
      resolveBindings = schemaEffect.schema.value;
      scopedCtx = enrichedCtx // resolveBindings;
      entityClass = resolveEntityClass targetKind resolveBindings;
    in
    {
      inherit
        targetKind
        resolveBindings
        scopedCtx
        entityClass
        ;
    };

  # Process a single schema resolve effect within the fold.
  processSingleResolve =
    entityKind: enrichedCtx: includeAspects: isFanOut: prevResults: schemaEffect:
    let
      inherit (decomposeSchemaEffect entityKind enrichedCtx schemaEffect)
        targetKind
        resolveBindings
        scopedCtx
        entityClass
        ;
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
            # Tag child scope with source policy — prevents the policy from
            # re-dispatching at entities it created (no self-referential cycles).
            sourcePolicyName = schemaEffect.__sourcePolicyName or null;
          }
        else if newAspectValues != [ ] then
          mkSupplementalResolution scopeHandlersForCtx ctxNames prevResults newAspectValues
        else
          fx.pure prevResults
      );

  # Emit late policy effects into a single sibling scope.
  emitLateForSibling =
    parentScope: parentFiredPolicies: allAspectPolicies: firedPerScope: sib:
    let
      dispatchKey = "${sib.targetKind}@${sib.scopeId}";
      alreadyFired = firedPerScope.${dispatchKey} or { };
      # Filter policies to those not already fired AND whose entity-kind
      # requirements match the target kind. A policy requiring { host, ... }
      # fires at host scopes but not at user scopes (which inherit host
      # context but are a different entity kind). This prevents policies
      # like to-os-outputs from re-firing at deeper entity scopes and
      # producing duplicate instantiates.
      #
      # Also exclude policies that already fired at the parent scope during
      # installPolicies. Output policies (to-packages, to-apps, etc.) fire
      # at flake-system scope and produce route effects. Without this check,
      # late dispatch re-fires them at entity scopes (host/home/user),
      # creating duplicate routes that leak packages across scope boundaries.
      entityKinds = den.lib.schemaUtil.schemaEntityKinds;
      latePolicies = lib.filterAttrs (
        name: policy:
        !(alreadyFired ? ${name})
        && !(parentFiredPolicies ? ${name})
        && (
          let
            policyArgs = builtins.functionArgs (policy.fn or policy);
            requiredEntityArgs = builtins.filter (
              k: builtins.elem k entityKinds && !(policyArgs.${k} or false)
            ) (builtins.attrNames policyArgs);
          in
          requiredEntityArgs == [ ] || builtins.elem sib.targetKind requiredEntityArgs
        )
      ) allAspectPolicies;
    in
    fx.bind fx.effects.state.get (
      state:
      let
        constraintRegistry = state.flatConstraintRegistry or { };
        isExcluded = name: builtins.any (e: e.type == "exclude") (constraintRegistry.${name} or [ ]);
        filteredPolicies = lib.filterAttrs (name: _: !isExcluded name) latePolicies;
        resolveCtx = sib.scopedCtx // {
          __entityKind = sib.targetKind;
        };
        lateResults = dispatchAspect filteredPolicies alreadyFired resolveCtx;
        late = extractTaggedEffects (map classifyPolicyResult lateResults);
        hasLateEffects =
          late.includeEffects != [ ]
          || late.routeEffects != [ ]
          || late.instantiateEffects != [ ]
          || late.provideEffects != [ ]
          || late.excludeEffects != [ ];
      in
      if filteredPolicies == { } || !hasLateEffects then
        fx.pure null
      else
        fx.bind
          (fx.send "push-scope" {
            scopedCtx = sib.scopedCtx;
            entityClass = sib.entityClass;
            inherit parentScope;
          })
          (
            { scopeHandlers, ... }:
            let
              # Strip `class` from propagated scope handlers — class is an
              # internal routing key and must not appear in __scopeKeys
              # (which take.exactly uses for exact-match detection).
              # class remains available via scope.provide for handler probing.
              userFacingHandlers = builtins.removeAttrs scopeHandlers [ "class" ];
            in
            fx.bind (fx.effects.scope.provide scopeHandlers (
              emitPolicyEffectsThen late (
                policyEmitIncludes late.includeEffects { parentScopeHandlers = userFacingHandlers; }
              )
            )) (_: fx.send "restore-scope" { inherit parentScope; })
          )
    );

  # Post-resolve pass: re-dispatch aspect policies registered by later siblings.
  # inLateDispatch is set true per-scope — push-scope resets it, restore-scope
  # restores the parent value.  This gives each scope level exactly one
  # late-dispatch opportunity while preventing O(N²) re-dispatch within the
  # same scope level.
  lateDispatchPass =
    siblingMetas:
    fx.bind (fx.effects.state.modify (st: st // { inLateDispatch = true; })) (
      _:
      fx.bind fx.effects.state.get (
        state:
        let
          scopedAspectPolicies = (state.scopedAspectPolicies or (_: { })) null;
          firedPerScope = (state.firedPolicyNames or (_: { })) null;
          parentScope = state.currentScope;
          # Only collect policies from the parent scope and sibling scopes —
          # not the global flat set.  Using flatAspectPolicies caused cross-host
          # contamination: unguarded policies (to-users, to-hosts) from sibling
          # host scopes would fire in unrelated host contexts.
          siblingScopes = map (s: s.scopeId) siblingMetas;
          relevantScopes = [ parentScope ] ++ siblingScopes;
          subtreePolicies = builtins.foldl' (
            acc: sid: acc // (scopedAspectPolicies.${sid} or { })
          ) { } relevantScopes;
          # Collect all policies that already fired at the parent scope
          # (under any entity kind). These should not re-fire at children
          # via late dispatch — they already produced their effects.
          parentFiredPolicies = builtins.foldl' (
            acc: key: if lib.hasSuffix "@${parentScope}" key then acc // (firedPerScope.${key} or { }) else acc
          ) { } (builtins.attrNames firedPerScope);
        in
        builtins.foldl' (
          acc: sib:
          fx.bind acc (
            _: emitLateForSibling parentScope parentFiredPolicies subtreePolicies firedPerScope sib
          )
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
  inherit processSchemaResolves;
}
