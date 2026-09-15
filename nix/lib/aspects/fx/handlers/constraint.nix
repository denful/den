# Effect handlers: register-constraint, check-constraint
# Manages the constraint registry (exclude, substitute, filter) and
# evaluates constraints against node identities during tree walk.
{
  lib,
  den,
  ...
}:
let
  lookupEntries =
    registry: nodeIdentity:
    let
      exact = registry.${nodeIdentity} or [ ];
      parts = lib.splitString "/" nodeIdentity;
      prefixes = lib.genList (i: lib.concatStringsSep "/" (lib.take (i + 1) parts)) (
        builtins.length parts - 1
      );
    in
    if registry == { } then
      exact
    else if builtins.length parts > 1 then
      exact ++ builtins.concatMap (p: registry.${p} or [ ]) prefixes
    else
      exact;

  # Chain-prefix ancestry: is `ownerChain` a prefix of the includes `chain`. The
  # shared scope-relevance atom (also consumed by compile-conditional.nix).
  isAncestorChain = chain: ownerChain: lib.take (builtins.length ownerChain) chain == ownerChain;

  filterByScope =
    currentChain: entries:
    let
      inScope =
        entry:
        (entry.scope or "global") == "global" || isAncestorChain currentChain (entry.ownerChain or [ ]);
    in
    builtins.filter inScope entries;

  # Cycle-guarded fold up the scopeParent chain from `scope`, merging each scope's
  # value (`at s`) into the accumulator via `merge`. The shared scope+ancestor walk
  # skeleton (constraint registry AND the guard pathSet, compile-conditional.nix).
  # Stops on null or any revisit — scopeParent can cycle in spawn/forward merged
  # sub-pipelines. Own/closer scopes are merged before ancestors.
  foldScopeAncestors =
    merge: scopeParentMap: at: scope:
    let
      go =
        seen: s: acc:
        if s == null || seen ? ${s} then
          acc
        else
          go (seen // { ${s} = true; }) (scopeParentMap.${s} or null) (merge acc (at s));
    in
    go { } scope { };

  # Self-or-ancestor raw-value claim lookup (foldScopeAncestors over one
  # policyClaimsByName bucket). Shared by registerPolicy (children.nix,
  # write path: appends a new claim when nothing matches) and raw-ref
  # exclude resolution (dispatch-policies.nix, read path). Both must judge
  # "is this the same registration" by the identical rule, so an exclude and
  # its target are matched exactly as registerPolicy would have matched
  # them. Whole-value `==`, not a projection: two claims differing only in
  # an attached label must not read as one registration.
  resolveClaim =
    scopeParentMap: scope: claimedEntries: target:
    let
      entriesByAncestorScope = foldScopeAncestors (a: b: a // b) scopeParentMap (s: {
        ${s} = builtins.filter (e: e.scope == s) claimedEntries;
      }) scope;
      sameScopeEntries = builtins.concatLists (builtins.attrValues entriesByAncestorScope);
    in
    {
      inherit sameScopeEntries;
      matchingClaim = lib.findFirst (e: target == e.value) null sameScopeEntries;
    };

  # The constraint registry relevant to a scope, as one identity→entries map —
  # the merge of the scope's own + ANCESTOR scopes' entries (cycle-guarded walk
  # up scopeParent). Replaces the fleet-wide flat registry: it is the SINGLE
  # lookup all readers share (check-constraint + the policy-name exclusion
  # filters), so the flat registry is gone. A SIBLING entity's excludes live under
  # the sibling's scope key — NOT an ancestor — and are therefore ABSENT, fixing
  # the eval-order sibling-leak (#613 analog) for BOTH aspect-content excludes
  # (`den.aspects.X.excludes`) and policy-name excludes. Schema-tier excludes
  # (`den.schema.KIND.excludes`) register at the resolved KIND scope and reach
  # descendants via the ancestor walk (the late-policy dispatch scopes to the
  # SIBLING it emits for — see scopedConstraintsForScope — so a kind's own
  # excludes are in scope). Cycle-guarded: scopeParent can cycle in spawn/forward
  # merged sub-pipelines, and check-constraint runs for EVERY node.
  collectScopedConstraints =
    scopedRegistry: scopeParentMap: scope:
    foldScopeAncestors (
      a: b:
      lib.zipAttrsWith (_: builtins.concatLists) [
        a
        b
      ]
    ) scopeParentMap (s: scopedRegistry.${s} or { }) scope;

  # The shared entry point: build the scope-relevant constraint registry from
  # pipeline state, FOR a given target scope. Every reader goes through this, so
  # there is ONE registry (no fleet-wide flat duplicate). The scope is explicit
  # because the LATE-policy dispatch (policy/schema emitLateForSibling) runs at the
  # PARENT scope but emits for a CHILD sibling — it must scope to the sibling
  # (where that sibling's + its kind's excludes live), not the parent. `scope ==
  # null` (bare-handler unit tests / empty state) ⇒ empty registry.
  scopedConstraintsForScope =
    state: scope:
    collectScopedConstraints ((state.scopedConstraintRegistry or (_: { })) null) (
      (state.scopeParent or (_: { }))
      null
    ) scope;

  # The common case: scope to the state's currentScope.
  scopedConstraintsFor = state: scopedConstraintsForScope state (state.currentScope or null);

  # A raw-ref exclude entry's OWN target identity, resolved the same way
  # registerPolicy assigned it: self-or-ancestor lookup in the claim
  # registry by raw value, from `scope`. null when the referenced policy
  # never actually registered anywhere reachable from `scope`. `scope` is
  # taken explicitly rather than read off `state.currentScope`: the
  # late-sibling caller resolves FOR a sibling scope while running AT its
  # parent's, and a claim registered only at the sibling's own scope is a
  # descendant of, not an ancestor of, the parent — invisible to a walk that
  # started there instead.
  resolveRawRefIdentity =
    state: scope: e:
    let
      scopeParentMap = (state.scopeParent or (_: { })) null;
      claimRegistry = (state.policyClaimsByName or (_: { })) null;
      claimedEntries = claimRegistry."name:${e.rawRef.name}" or [ ];
      resolved = resolveClaim scopeParentMap scope claimedEntries e.rawRef;
    in
    if resolved.matchingClaim != null then resolved.matchingClaim.identity else null;

  # Is `name` excluded by `registry` (a constraint registry already scoped to
  # `scope` — see scopedConstraintsFor/scopedConstraintsForScope)? Two arms:
  # (a) a direct match under name's own bucket, for entries with no rawRef
  # (schema/aspect-content excludes, and the dead string-policy-exclude route
  # — both key on bare identity already); (b) a rawRef-tagged entry anywhere
  # in the registry whose raw-value resolution names `name` precisely. A
  # rawRef entry whose target never registered resolves to null and excludes
  # nothing — naming a record that was never included must not fall back to
  # matching some unrelated policy that happens to share its bare name. The
  # single entry point for both the initial per-scope dispatch
  # (dispatch-policies.nix, scope = state.currentScope) and the late-sibling
  # re-dispatch (policy/schema.nix emitLateForSibling, scope = sib.scopeId) —
  # both must exclude the SAME claimant, or a claimant filtered from one
  # still fires through the other.
  #
  # CURRIED DELIBERATELY: `name` is the last argument and everything above it
  # is a partial application both callers make ONCE, outside their filterAttrs
  # lambda. Nothing in arm (b) depends on the name being tested, so applying
  # all four arguments per candidate rebuilt the whole rawRef resolution for
  # each of P policy names. Callers must keep hoisting the partial application;
  # re-inlining a fully-applied call inside a per-name lambda silently restores
  # the P factor below.
  #
  # Cost, with the hoist: O(E + R × D × C) once per dispatch, plus O(1) per
  # candidate name. Without it, every term was multiplied by P.
  #   E = constraint entries in the scoped registry — per-entity, bounded by
  #       how many excludes/handleWith one aspect tree declares, not fleet-wide.
  #   R = rawRef excludes in scope.
  #   D = scopes visited per resolveClaim ancestor walk — small (e.g. a
  #       user-scope walk visits 4: self, host, system, and the root ""
  #       scope), bounded by scope-tree depth, not fleet-wide.
  #   C = size of the claim bucket resolveClaim scans at each visited scope
  #       (claimRegistry."name:<n>" — builtins.filter + findFirst over it).
  #       This bucket is FLEET-WIDE, not per-entity: policyClaimsByName
  #       accumulates every claim under that bare name across the whole run,
  #       regardless of scope. Traced: N entities each declaring their own
  #       "tools" policy grows C to N while the entity-scoped walk still
  #       keeps exactly 1 matching claim. So with R > 0 and multiple entities
  #       declaring a same-named policy, the R × D × C term is linear in
  #       fleet size N — do not read E's per-entity bound as covering the
  #       whole cost; E and C are scoped oppositely and must not be merged
  #       under one "bounded per-entity" claim.
  #
  # The rawRef arm now resolves EVERY rawRef entry rather than stopping at the
  # first whose identity matches. That is deliberate: which entries got
  # resolved previously depended on the order candidate names arrived in, so
  # any error reachable through resolveClaim surfaced for some dispatch orders
  # and not others.
  isPolicyExcluded =
    state: scope: registry:
    let
      rawRefEntries = builtins.filter (e: e.type == "exclude" && (e.rawRef or null) != null) (
        builtins.concatLists (builtins.attrValues registry)
      );
      rawRefExcluded = lib.genAttrs (builtins.filter (id: id != null) (
        map (resolveRawRefIdentity state scope) rawRefEntries
      )) (_: true);
    in
    name:
    let
      directEntries = registry.${name} or [ ];
      directApplies = e: e.type == "exclude" && (e.rawRef or null) == null;
    in
    builtins.any directApplies directEntries || rawRefExcluded ? ${name};

  # The `den:` diagnostics for raw-ref excludes that resolved to no claim
  # ANYWHERE in a finished resolution — a user naming a record den never found,
  # suppressing nothing, previously in silence.
  #
  # DELIBERATELY NOT ON THE PER-SCOPE PATH. resolveRawRefIdentity returning null
  # for one scope is ordinary correct behaviour: an exclude registered at host
  # scope reaches every descendant scope, and the policy it names is typically
  # claimed in only some of them. Warning from isPolicyExcluded would fire on
  # every non-matching scope of every legitimate exclude. The warnable condition
  # is global — no claim in the whole run carries this reference — so it takes
  # the TERMINAL state, and is read once at post-assembly (resolve.nix's
  # fxResolveFull), never during dispatch.
  #
  # Whole-value `==` against the claim bucket, matching resolveClaim's rule
  # exactly, minus its scope walk: the question here is whether the referenced
  # record registered AT ALL, not whether it registered somewhere a given scope
  # can see. Deliberately the weaker test — a claim in an unreachable sibling
  # scope stays silent rather than risk a false alarm.
  unmatchedRawRefExcludes =
    state:
    let
      registry = (state.scopedConstraintRegistry or (_: { })) null;
      claims = (state.policyClaimsByName or (_: { })) null;
      rawRefEntries = builtins.filter (e: e.type == "exclude" && (e.rawRef or null) != null) (
        builtins.concatMap (scopeData: builtins.concatLists (builtins.attrValues scopeData)) (
          builtins.attrValues registry
        )
      );
      isUnmatched = e: !(builtins.any (c: c.value == e.rawRef) (claims."name:${e.rawRef.name}" or [ ]));
    in
    lib.unique (
      map (
        e:
        "den: exclude in aspect '${e.owner}' names policy '${e.rawRef.name}', which never registered in this resolution — the exclude suppresses nothing"
      ) (builtins.filter isUnmatched rawRefEntries)
    );

  entryToResume =
    entry:
    if entry.type == "exclude" then
      {
        action = "exclude";
        inherit (entry) owner;
      }
    else if entry.type == "substitute" then
      {
        action = "substitute";
        replacement = entry.getReplacement null;
        inherit (entry) owner;
      }
    else
      { action = "keep"; };

  constraintRegistryHandler = {
    "register-constraint" =
      { param, state }:
      let
        inherit (state) currentScope;
        ownerChain = ((state.scopedIncludesChain or (_: { })) null).${currentScope} or [ ];
        scope = param.scope or "subtree";
      in
      if param.type == "filter" then
        let
          filterEntry = {
            inherit (param) predicate;
            owner = param.owner or "<anon>";
            inherit scope ownerChain;
          };
        in
        {
          resume = null;
          state = state // {
            flatConstraintFilters = (state.flatConstraintFilters or [ ]) ++ [ filterEntry ];
          };
        }
      else
        let
          entry = {
            inherit (param) type;
            getReplacement = param.getReplacement or (_: null);
            owner = param.owner or "<anon>";
            # Carried for dispatch-policies.nix's raw-ref exclude resolution
            # (null for every non-policy constraint — see children.nix's
            # excludeList).
            rawRef = param.rawRef or null;
            inherit scope ownerChain;
          };
        in
        {
          resume = null;
          # Only the scope-keyed registry is written; all readers go through
          # scopedConstraintsFor (entity-scoped: scope + ancestors), so the former
          # fleet-wide flatConstraintRegistry — which leaked excludes across
          # siblings — is gone.
          state =
            let
              all = (state.scopedConstraintRegistry or (_: { })) null;
              inherit (state) currentScope;
              scopeData = all.${currentScope} or { };
              updatedRegistry = all // {
                ${currentScope} = scopeData // {
                  ${param.identity} = (scopeData.${param.identity} or [ ]) ++ [ entry ];
                };
              };
            in
            state // { scopedConstraintRegistry = _: updatedRegistry; };
        };

    "check-constraint" =
      { param, state }:
      let
        nodeIdentity = if builtins.isAttrs param then param.identity else param;
        aspect = if builtins.isAttrs param then param.aspect or null else null;
        currentChain = ((state.scopedIncludesChain or (_: { })) null).${state.currentScope} or [ ];
        # #613 analog: entity-scoped registry (scopedConstraintsFor: scope +
        # ancestors), NOT the fleet-wide flat registry — a sibling entity's exclude
        # must not suppress this node. filterByScope still applies for within-scope
        # include nesting.
        allEntries = lookupEntries (scopedConstraintsFor state) nodeIdentity;
        scopedEntries = filterByScope currentChain allEntries;
        firstEntry = if scopedEntries == [ ] then null else builtins.head scopedEntries;
      in
      if firstEntry != null then
        {
          resume = entryToResume firstEntry;
          inherit state;
        }
      else
        let
          scopedFilters = filterByScope currentChain (state.flatConstraintFilters or [ ]);
          failedFilter =
            if aspect != null then lib.findFirst (f: !(f.predicate aspect)) null scopedFilters else null;
        in
        if failedFilter != null then
          {
            resume = {
              action = "exclude";
              inherit (failedFilter) owner;
            };
            inherit state;
          }
        else
          {
            resume = {
              action = "keep";
            };
            inherit state;
          };
  };
in
{
  inherit
    constraintRegistryHandler
    lookupEntries
    isAncestorChain
    foldScopeAncestors
    resolveClaim
    isPolicyExcluded
    unmatchedRawRefExcludes
    collectScopedConstraints
    scopedConstraintsFor
    scopedConstraintsForScope
    ;
}
