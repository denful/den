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
  inherit (den.lib.synthesizePolicies) resolveArgsSatisfied;
  inherit (import ../handlers/constraint.nix { inherit lib den; })
    scopedConstraintsForScope
    isPolicyExcluded
    ;

  # Identity by id_hash when both records carry one, else by value, minus the
  # per-scope `hasAspect` decomposeSchemaEffect adds.
  sameEntity =
    a: b:
    if a ? id_hash && b ? id_hash then
      a.id_hash == b.id_hash
    else
      builtins.removeAttrs a [ "hasAspect" ] == builtins.removeAttrs b [ "hasAspect" ];

  # Two scopes bind a value the same way: entities by identity, others by value.
  sameBinding = a: b: if builtins.isAttrs a && builtins.isAttrs b then sameEntity a b else a == b;

  # Two registry entries are one policy when they hold the same record (its
  # `fn` slot, children.nix registerPolicy); two records sharing a name are
  # two policies. An entry registered without a slot is matched by name.
  samePolicy =
    a: b:
    let
      sa = a.fnSlot or null;
      sb = b.fnSlot or null;
    in
    sa == null || sb == null || sa == sb;
  # The policies a pass offered: each name with every record offered under it.
  addSeen =
    seen: reg:
    builtins.foldl' (acc: k: acc // { ${k} = (acc.${k} or [ ]) ++ [ reg.${k} ]; }) seen (
      builtins.attrNames reg
    );
  seenHas =
    seen: name: policy:
    builtins.any (samePolicy policy) (seen.${name} or [ ]);

  # The fired set grouped by scope, once per pass, so a sibling's offered
  # scopes are looked up rather than every fired key scanned per sibling.
  firedByScope =
    firedPerScope:
    let
      entries = lib.concatMap (
        key:
        let
          parts = lib.splitString "@" key;
        in
        lib.optional (builtins.length parts > 1) {
          at = lib.concatStringsSep "@" (builtins.tail parts);
          fired = firedPerScope.${key};
        }
      ) (builtins.attrNames firedPerScope);
    in
    builtins.mapAttrs (_: es: builtins.foldl' (acc: e: acc // e.fired) { } es) (
      builtins.groupBy (e: e.at) entries
    );

  # Policies that already fired in one of `offered` (under any entity kind).
  firedInScopes =
    byScope: offered: builtins.foldl' (acc: s: acc // (byScope.${s} or { })) { } offered;

  describeRecord =
    r: "${r.name or "<unnamed>"}${lib.optionalString (r ? id_hash) " (id_hash ${r.id_hash})"}";

  # A binding is matched to an entity scope by id_hash, or by value when
  # neither record has one. A record with an id_hash and one without are
  # different entities, unless they share a name: then den cannot tell, and a
  # quiet mismatch would silently fire none of the entity's rules.
  mixedIdHash =
    kind: a: others:
    let
      clash = lib.findFirst (b: (b.name or null) != null && b.name == (a.name or null)) null others;
    in
    if clash == null then
      [ ]
    else
      throw "den: two `${kind}` records, ${describeRecord a} and ${describeRecord clash}, share a name but only one carries an id_hash, so den cannot tell whether they are one entity; give both an id_hash, or neither";

  # "eq", "ne", or "fn" when the values differ only in function-valued
  # attributes, which Nix compares unequal unless they are the same value.
  valueDiff =
    a: b:
    if a == b then
      "eq"
    else if builtins.isFunction a && builtins.isFunction b then
      "fn"
    else if builtins.isAttrs a && builtins.isAttrs b then
      let
        names = builtins.attrNames a;
        isLeaf = n: !(builtins.isAttrs a.${n}) && !(builtins.isFunction a.${n});
      in
      if names != builtins.attrNames b then
        "ne"
      else if builtins.any (n: isLeaf n && a.${n} != b.${n}) names then
        "ne"
      else
        let
          diffs = map (n: valueDiff a.${n} b.${n}) (builtins.filter (n: !isLeaf n) names);
        in
        if builtins.elem "ne" diffs then
          "ne"
        else if builtins.elem "fn" diffs then
          "fn"
        else
          "eq"
    else
      "ne";

  sameByValue =
    kind: a: b:
    let
      d = valueDiff (builtins.removeAttrs a [ "hasAspect" ]) (builtins.removeAttrs b [ "hasAspect" ]);
    in
    if d == "fn" then
      throw "den: two `${kind}` records named ${a.name or "<unnamed>"} differ only in function values, so den cannot tell whether they are one entity; give them an id_hash"
    else
      d == "eq";

  # Pending re-pass entries for `kind`, bucketed by id_hash ("" for records
  # without one): the entries waiting on `record`'s entity.
  pendingFor =
    kind: byKind: record:
    let
      noId = byKind."" or { };
      withId = builtins.filter (b: b != "" && byKind.${b} != { }) (builtins.attrNames byKind);
    in
    if record ? id_hash then
      mixedIdHash kind record (map (p: p.record) (builtins.attrValues noId))
      ++ builtins.attrValues (byKind.${record.id_hash} or { })
    else
      mixedIdHash kind record (
        lib.concatMap (b: map (p: p.record) (builtins.attrValues byKind.${b})) withId
      )
      ++ builtins.filter (p: sameByValue kind p.record record) (builtins.attrValues noId);

  # A sibling's binding whose entity has not resolved yet is offered once that
  # entity resolves: a re-pass of the sibling with the entity's registry, so
  # the order in which entities resolve does not decide which rules fire. An
  # entry is consumed when it re-passes and the done set refuses a second
  # (sibling, kind) re-pass, so re-passes are bounded by the entries late
  # passes add: one per sibling and kind its tree does not bind. That count is
  # the named cap, maxBoundRepasses, a guard on the construction.
  repassBound =
    targetKind: scopedCtx: entityScope:
    fx.bind fx.effects.state.get (
      state:
      let
        here = state.currentScope;
        record = scopedCtx.${targetKind} or null;
        pendingAll = (state.boundRepassPending or (_: { })) null;
        byKind = pendingAll.${targetKind} or { };
        done = state.boundRepassDone or { };
        key = p: "${p.sib.scopeId}|${p.kind}";
        pending =
          if byKind == { } || !(builtins.isAttrs record) then
            [ ]
          else
            builtins.filter (p: !(done ? ${key p})) (pendingFor targetKind byKind record);
        consumed = builtins.groupBy (p: p.record.id_hash or "") pending;
        count = (state.boundRepassCount or 0) + builtins.length pending;
        cap = state.maxBoundRepasses or 0;
      in
      if pending == [ ] then
        fx.pure null
      else if count > cap then
        throw "den: ${toString count} late re-passes for bindings resolved after their binders exceed maxBoundRepasses (${toString cap}), the number of such bindings late dispatch recorded; each should re-pass at most once"
      else
        fx.bind
          (fx.effects.state.modify (
            st:
            st
            // {
              boundRepassCount = count;
              boundRepassDone = (st.boundRepassDone or { }) // lib.genAttrs (map key pending) (_: true);
              boundRepassPending =
                _:
                pendingAll
                // {
                  ${targetKind} =
                    byKind
                    // builtins.mapAttrs (
                      bucket: ps: builtins.removeAttrs (byKind.${bucket} or { }) (map (p: p.sib.scopeId) ps)
                    ) consumed;
                };
            }
          ))
          (
            _:
            fx.bind fx.effects.state.get (
              st:
              let
                firedPerScope = (st.firedPolicyNames or (_: { })) null;
                firedHere = firedInScopes (firedByScope firedPerScope) [ entityScope ];
              in
              builtins.foldl' (
                acc: p:
                fx.bind acc (
                  _:
                  fx.bind fx.effects.state.get (
                    st':
                    let
                      policies = (st'.scopedAspectPolicies or (_: { })) null;
                      # What the sibling's first pass offered, and its own
                      # registry: those already had their chance to fire.
                      seen = addSeen p.seen (policies.${p.sib.scopeId} or { });
                    in
                    fx.bind
                      (emitLateForSibling p.parentScope [ entityScope ] firedHere policies firedPerScope seen p.sib)
                      (_: fx.effects.state.modify (st'': st'' // { currentScope = here; }))
                  )
                )
              ) (fx.pure null) pending
            )
          )
    );

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
          fx.bind (fx.send "resolve-schema-entity" {
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
          }) (results: fx.bind (repassBound targetKind scopedCtx ctxNames) (_: fx.pure results))
        else if newAspectValues != [ ] then
          mkSupplementalResolution scopeHandlersForCtx ctxNames prevResults newAspectValues
        else
          fx.pure prevResults
      );

  # Emit late policy effects into a single sibling scope.
  emitLateForSibling =
    parentScope: ancestorScopes: parentFiredPolicies: scopedAspectPolicies: firedPerScope: seen: sib:
    let
      # Runtime-include policies are subtree-scoped: a policy registered via a
      # scope's own includes applies only to that scope's subtree, never to
      # siblings. The policies eligible at `sib` are therefore exactly those
      # registered at an ancestor-or-self scope — the parent (host), whose
      # subtree contains every user, plus `sib`'s own. A sibling user's includes
      # (an opt-in battery's policy, a per-user `to-users` policy, …) never fire
      # at OTHER users.
      allAspectPolicies =
        builtins.foldl' (acc: s: (scopedAspectPolicies.${s} or { }) // acc) { } ancestorScopes
        // (scopedAspectPolicies.${sib.scopeId} or { });
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
          policyArgs = lib.functionArgs (policy.fn or policy);
          requiredEntityArgs = builtins.filter (
            k: builtins.elem k entityKinds && !(policyArgs.${k} or false)
          ) (builtins.attrNames policyArgs);
        in
        !(alreadyFired ? ${name})
        && !(seenHas seen name policy)
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
        # Applied once, outside the lambda — see isPolicyExcluded's currying note.
        excluded = isPolicyExcluded state sib.scopeId constraintRegistry;
        # A policy an ancestor scope could already dispatch with the same bound
        # arguments fired there (late firings are not recorded in the fired
        # set), so it does not fire again here: offering a grandparent's
        # registry must not re-fire its `{ system }` policies at every user.
        scopeCtxs = (state.scopeContexts or (_: { })) null;
        boundOf =
          ctx: policy:
          builtins.filter (k: ctx ? ${k}) (builtins.attrNames (lib.functionArgs (policy.fn or policy)));
        # The same instance: the same declared arguments bound, to the same
        # values. Names alone are not enough where a scope rebinds one (a guest
        # binds `host` to itself).
        sameInstanceAbove =
          name: policy:
          builtins.any (
            a:
            let
              actx = scopeCtxs.${a} or { };
              names = boundOf actx policy;
            in
            resolveArgsSatisfied (policy.fn or policy) actx
            && names == boundOf sib.scopedCtx policy
            && builtins.all (k: sameBinding actx.${k} sib.scopedCtx.${k}) names
          ) (registeredFrom name);
        # Only an ancestor at or below the farthest one that registers the
        # policy could have run it: one registered at the sibling after its own
        # dispatch (a late include) is new everywhere above.
        registeredFrom =
          name:
          let
            regIdx = builtins.filter (
              i: (scopedAspectPolicies.${builtins.elemAt ancestorScopes i} or { }) ? ${name}
            ) (lib.range 0 (builtins.length ancestorScopes - 1));
          in
          if regIdx == [ ] then [ ] else lib.take (lib.last regIdx + 1) ancestorScopes;
        # The sibling's own dispatch already ran these, whatever they returned.
        ranAtSib = ((state.installDispatched or (_: { })) null).${sib.scopeId} or { };
        # Late dispatch already ran this instance here, in an earlier pass or a
        # bound re-pass: the same policy with the same bound argument values.
        # Every pass at one scope reuses its sib.scopedCtx, so today this equals
        # policy-plus-scope; keyed by instance so a future context change can't under-reach.
        lateRanAtSib = ((state.lateDispatched or (_: { })) null).${dispatchKey} or { };
        instanceOf = policy: lib.genAttrs (boundOf sib.scopedCtx policy) (k: sib.scopedCtx.${k});
        lateRan =
          name: policy:
          let
            inst = instanceOf policy;
          in
          builtins.any (
            prev:
            samePolicy prev.policy policy
            && builtins.attrNames prev.inst == builtins.attrNames inst
            && builtins.all (k: sameBinding prev.inst.${k} inst.${k}) (builtins.attrNames inst)
          ) (lateRanAtSib.${name} or [ ]);
        filteredPolicies = lib.filterAttrs (
          name: policy:
          !excluded name
          && !(ranAtSib ? ${name})
          && !(lateRan name policy)
          && !(sameInstanceAbove name policy)
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
        recordLate = fx.effects.state.modify (
          st:
          st
          // {
            lateDispatched =
              _:
              let
                prev = (st.lateDispatched or (_: { })) null;
              in
              prev
              // {
                ${dispatchKey} =
                  let
                    here = prev.${dispatchKey} or { };
                  in
                  builtins.foldl' (
                    acc: name:
                    let
                      policy = filteredPolicies.${name};
                    in
                    acc
                    // {
                      ${name} = (acc.${name} or [ ]) ++ [
                        {
                          inherit policy;
                          inst = instanceOf policy;
                        }
                      ];
                    }
                  ) here (builtins.attrNames filteredPolicies);
              };
          }
        );
      in
      if filteredPolicies == { } then
        fx.pure null
      else if !hasLateEffects then
        recordLate
      else
        fx.bind recordLate (
          _:
          fx.bind
            (fx.bind
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
            )
            # The late includes may carry `provides` of their own, registering
            # policies at `sib` after its dispatch already ran — without this
            # re-pass a `to-hosts` reached through `<host>.provides.<user>` is
            # silently dropped.
            (
              _:
              fx.bind fx.effects.state.get (
                state':
                let
                  scopedAspectPolicies' = (state'.scopedAspectPolicies or (_: { })) null;
                  seen' = addSeen seen allAspectPolicies;
                  fresh = lib.filterAttrs (name: policy: !(seenHas seen' name policy)) (
                    scopedAspectPolicies'.${sib.scopeId} or { }
                  );
                in
                if fresh == { } then
                  fx.pure null
                else
                  emitLateForSibling parentScope ancestorScopes parentFiredPolicies scopedAspectPolicies'
                    firedPerScope
                    seen'
                    sib
              )
            )
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
          # The parent and every scope above it, nearest first: a policy
          # registered at any of them fires where its relata are bound, not only
          # one registered at the parent (an `environment`'s `{ host, user }`
          # policy reaches the users two levels down).
          scopeParents = (state.scopeParent or (_: { })) null;
          ancestorScopes =
            let
              go =
                seen: s:
                if s == null || seen ? ${s} then
                  [ ]
                else
                  [ s ] ++ go (seen // { ${s} = true; }) (scopeParents.${s} or null);
            in
            go { } parentScope;
          # A tree ancestor whose own entity the sibling binds to a different
          # entity is not offered: a guest binds `host` to itself, so its host's
          # policies stay with the host, as guests are their own hosts.
          scopeKinds = (state.scopeEntityKind or (_: { })) null;
          scopeCtxsL = (state.scopeContexts or (_: { })) null;
          keptAncestorsFor =
            sib:
            builtins.filter (
              a:
              let
                kind = scopeKinds.${a} or null;
                own = if kind == null then null else (scopeCtxsL.${a} or { }).${kind} or null;
              in
              own == null || !(sib.scopedCtx ? ${kind}) || sameEntity sib.scopedCtx.${kind} own
            ) ancestorScopes;
          boundIndex = (state.boundEntityIndex or (_: { })) null;
          # The scopes of the entity a sibling binds for `kind`, by id_hash, or
          # by value among the kind's records without one.
          boundScopesFor =
            kind: record:
            let
              ix = boundIndex.${kind} or { };
              noId = ix."" or { };
              withId = builtins.filter (b: b != "") (builtins.attrNames ix);
              recordAt = sid: (scopeCtxsL.${sid} or { }).${kind};
            in
            if record ? id_hash then
              mixedIdHash kind record (map recordAt (builtins.attrNames noId))
              ++ builtins.attrNames (ix.${record.id_hash} or { })
            else
              mixedIdHash kind record (lib.concatMap (b: map recordAt (builtins.attrNames ix.${b})) withId)
              ++ builtins.filter (sid: sameByValue kind record (recordAt sid)) (builtins.attrNames noId);
          # Plus the scope of every entity the sibling binds outside its tree:
          # a policy applies where the scope's binding for its registrant's
          # kind is that registrant, which for an ordinary host is the tree.
          # Only kinds no kept ancestor supplies are searched: id_hash is
          # parent-blind, so tux@iceberg must not find tux@igloo's scope.
          offerFor =
            sib:
            let
              kept = keptAncestorsFor sib;
              keptSet = lib.genAttrs kept (_: true);
              treeKinds = lib.genAttrs (builtins.filter (k: k != null) (map (a: scopeKinds.${a} or null) kept)) (
                _: true
              );
              boundKinds = builtins.filter (
                k:
                k != sib.targetKind
                && !(treeKinds ? ${k})
                && schemaEntityKindsSet ? ${k}
                && builtins.isAttrs sib.scopedCtx.${k}
              ) (builtins.attrNames sib.scopedCtx);
              lookups = map (k: {
                kind = k;
                scopes = builtins.filter (s: s != sib.scopeId && !(keptSet ? ${s})) (
                  boundScopesFor k sib.scopedCtx.${k}
                );
              }) boundKinds;
              offered = kept ++ lib.concatMap (l: l.scopes) lookups;
            in
            {
              inherit sib offered;
              # Bindings whose entity has not resolved yet: offered once it
              # does (repassBound).
              unresolved = map (l: l.kind) (builtins.filter (l: l.scopes == [ ]) lookups);
              # The names this pass offers; a re-pass does not offer them again.
              seen = builtins.foldl' (acc: s: addSeen acc (scopedAspectPolicies.${s} or { })) { } offered;
            };
          offers = map offerFor siblingMetas;
          firedBy = firedByScope firedPerScope;
        in
        fx.bind
          (fx.effects.state.modify (
            st:
            st
            // {
              # The cap on bound re-passes: one per binding a late pass found
              # unresolved.
              maxBoundRepasses =
                (st.maxBoundRepasses or 0) + builtins.foldl' (n: o: n + builtins.length o.unresolved) 0 offers;
              # Behind a thunk: the trampoline deepSeqs state each step, and
              # these hold whole entity records. Keyed by kind, id_hash and
              # sibling, so a repeated batch does not add a sibling twice.
              boundRepassPending =
                let
                  prev = (st.boundRepassPending or (_: { })) null;
                  added = lib.concatMap (
                    o:
                    map (k: {
                      kind = k;
                      record = o.sib.scopedCtx.${k};
                      inherit parentScope;
                      inherit (o) sib seen;
                    }) o.unresolved
                  ) offers;
                  insert =
                    acc: e:
                    let
                      bucket = e.record.id_hash or "";
                      byKind = acc.${e.kind} or { };
                      entries = byKind.${bucket} or { };
                    in
                    if entries ? ${e.sib.scopeId} then
                      acc
                    else
                      acc
                      // {
                        ${e.kind} = byKind // {
                          ${bucket} = entries // {
                            ${e.sib.scopeId} = e;
                          };
                        };
                      };
                in
                _: builtins.foldl' insert prev added;
            }
          ))
          (
            _:
            builtins.foldl' (
              acc: o:
              fx.bind acc (
                _:
                emitLateForSibling parentScope o.offered (firedInScopes firedBy o.offered) scopedAspectPolicies
                  firedPerScope
                  { }
                  o.sib
              )
            ) (fx.pure null) offers
          )
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
    # A single child gets the late pass too: whether a policy registered above
    # fires where its arguments are bound cannot depend on how many children
    # the resolve has (a guest with one user got none).
    if schemaEffects == [ ] || isLatePass then
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
            # The pass sets inLateDispatch for the policies it emits; reset it
            # after, so a later batch at this scope level gets its own pass.
            fx.bind (lateDispatchPass siblingMetas) (
              _:
              fx.bind (fx.effects.state.modify (
                st: st // { inLateDispatch = preState.inLateDispatch or false; }
              )) (_: fx.pure allResults)
            )
          )
      );
in
{
  inherit processSchemaResolves;
}
