# Schema resolve processing — entity scope transitions and fan-out.
{
  lib,
  fx,
  den,
  identity,
  constantHandler,
  mkScopeId,
  schemaEntityKinds,
  schemaEntityKindsSet,
  classifyPolicyResult,
  extractTaggedEffects,
  dispatchAspect,
  emitPolicyEffectsThen,
  policyEmitIncludes,
  mkSupplementalResolution,
}:
let
  inherit (import ../handlers/constraint.nix { inherit lib den; })
    scopedConstraintsForScope
    isPolicyExcluded
    ;

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
      rawScopedCtx = enrichedCtx // resolveBindings;
      entityClass = resolveEntityClass targetKind resolveBindings;

      # In-context `.hasAspect` answers PROJECTED membership — what's delivered
      # into this scope (incl. `provides`), not the structural registry tree. The
      # owning host's production run bucketed each scope's path set under
      # `__pathSetByScope`, RE-KEYED by entity identity (`id_hash`) at the entity
      # surface (entities/_types.nix:pathSetByScopeOption). The lookup is pure and
      # forced lazily (at a class-module `mkIf`), so it never re-enters the resolve
      # that produced it — except from an `includes` position, which forces the
      # host's own in-flight `__resolveResult` and recurses. So: don't decide
      # includes from it.
      #
      # Per the projected-hasAspect spec, EVERY in-context entity-kind binding
      # answers membership at the ACTIVE (consuming) scope — "is X delivered into
      # THIS scope" — keyed by ONE shared scope id, not each entity's own. After
      # the id_hash re-key the active scope's bucket is the consuming (target)
      # entity's id_hash (the deepest scope in ctx). Keying per-entity made
      # `host.hasAspect` read the host's OWN bucket, blinding it to aspects the
      # host delivers DOWN to its users via `provides.to-users` — those resolve
      # under the user scope, so only the active (consuming) bucket holds them.
      overrideKinds = builtins.filter (
        k: schemaEntityKindsSet ? ${k} && builtins.isAttrs (rawScopedCtx.${k} or null)
      ) (builtins.attrNames rawScopedCtx);
      # Owner = topmost ancestor along targetKind's parent chain whose ctx binding
      # carries a production bucket; falls back to the target itself. (Generic form
      # of "the host run buckets every descendant scope".)
      ownerChain = den.lib.aspects.fx.argClass.ancestorChain den.schema targetKind;
      ownerKind = lib.findFirst (
        k: builtins.isAttrs (rawScopedCtx.${k} or null) && rawScopedCtx.${k} ? __pathSetByScope
      ) targetKind (lib.reverseList ownerChain);
      ownerPathSet = rawScopedCtx.${ownerKind}.__pathSetByScope or { };
      # The active scope = the consuming (target) entity's bucket — the deepest
      # scope in ctx. Shared by every binding so `host`/`user`/etc. all answer
      # "delivered into THIS scope", per the spec.
      projected = den.lib.aspects.mkProjectedHasAspect {
        pathSetByScope = ownerPathSet;
        key = rawScopedCtx.${targetKind}.id_hash or null;
      };
      scopedCtx =
        rawScopedCtx // lib.genAttrs overrideKinds (k: rawScopedCtx.${k} // { hasAspect = projected; });
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
    parentScope: parentFiredPolicies: scopedAspectPolicies: firedPerScope: sib:
    let
      # Runtime-include policies are subtree-scoped: a policy registered via a
      # scope's own includes applies only to that scope's subtree, never to
      # siblings. The policies eligible at `sib` are therefore exactly those
      # registered at an ancestor-or-self scope — the parent (host), whose
      # subtree contains every user, plus `sib`'s own. A sibling user's includes
      # (an opt-in battery's policy, a per-user `to-users` policy, …) never fire
      # at OTHER users.
      allAspectPolicies =
        (scopedAspectPolicies.${parentScope} or { }) // (scopedAspectPolicies.${sib.scopeId} or { });
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
        let
          policyArgs = builtins.functionArgs (policy.fn or policy);
          requiredEntityArgs = builtins.filter (
            k: builtins.elem k entityKinds && !(policyArgs.${k} or false)
          ) (builtins.attrNames policyArgs);
        in
        !(alreadyFired ? ${name})
        && !(parentFiredPolicies ? ${name})
        # `self`-guarded policies fire only at their own registration scope
        # (during the initial dispatch); they must never re-fire at descendant
        # scopes via the fan-out. This is what makes `{ self, ... }:` mean
        # "fire once here", as opposed to `{ <kind>, ... }:` which fans.
        && !(policyArgs ? self)
        && (requiredEntityArgs == [ ] || builtins.elem sib.targetKind requiredEntityArgs)
      ) allAspectPolicies;
    in
    fx.bind fx.effects.state.get (
      state:
      let
        # Entity-scoped (NOT fleet-wide) — a sibling entity's policy-exclude must
        # not filter this sibling's late policies (#613 analog).
        # Scope to the SIBLING being dispatched (`sib.scopeId`), not the current
        # (parent) scope: the late dispatch runs at the parent but emits FOR the
        # child sibling, and the relevant excludes (e.g. den.schema.flake-system.
        # excludes) register at the sibling/descendant scope, not an ancestor.
        constraintRegistry = scopedConstraintsForScope state sib.scopeId;
        filteredPolicies = lib.filterAttrs (
          name: _: !isPolicyExcluded state sib.scopeId constraintRegistry name
        ) latePolicies;
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
          || late.excludeEffects != [ ]
          || late.spawnEffects != [ ];
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
          # Eligibility is decided per-sibling in emitLateForSibling (ancestor-or-
          # self scoping): parent-registered policies fan to all children, but a
          # sibling's own runtime-include policies stay in its own subtree.  This
          # supersedes the older parent+all-siblings union, which leaked a
          # sibling's includes across to other siblings (cross-host contamination
          # was already excluded; cross-sibling-within-host was not).
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
            _: emitLateForSibling parentScope parentFiredPolicies scopedAspectPolicies firedPerScope sib
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
