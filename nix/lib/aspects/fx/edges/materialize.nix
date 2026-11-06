# materialize.nix — the edge materializer (spec §3c "materialization"). Given a
# context projection Π and the edges targeting a root, produce the root's
# per-class content. This is the single mechanism that replaces the phase-fold
# re-entries' final extraction; phase ordering becomes edge toposort (corollary
# 5) as later mechanisms are ported.
#
# The mode arms are split across files: `merge` (default-fold port) is live here;
# `nest`/`nest-verbatim` (route delivery via materializeRouteEdge) and the synthesize
# (complex-forward) + provides edge materialization live in edges/route.nix +
# edges/provides.nix. The else-throw in the `materialize` switch below is NOT a
# stub — it is permanently correct: `assembleSubtree` carries merge edges only;
# route nest/nest-verbatim + synthesize delivery + provides are folded upstream by
# the unified ordered-dispatch engine (edges/materialize-unified.nix), which reuses
# those per-spec materializers and calls assembleSubtree for the final merge.
#
# The spawn port is `assembleSpawnSubtree` (below): the spawn's provides + routes
# fold + its isolation-BLIND, dedup-FREE final extraction, expressed over this
# machinery via materializeUnified with the `isolationMode = "blind"` +
# `dedupMode = "raw"` Π dials and an explicit `allScopeIds` subtree-universe
# override.
#
# DESIGN INVARIANTS (spec §2 corollaries; enforced by the entity-isolation suite
# and the delivery-edges fixtures):
#   - `materialize` (the mode switch) contains the ONLY mode switch
#     (merge | nest | nest-verbatim).
#   - The mode switch carries NO mechanism vocabulary (no route/provides/spawn/
#     instantiate names): mechanisms are dissolved into edges before they reach
#     it. Mechanism-specific Π-*builders* (e.g. `assembleSpawnSubtree`) MAY name
#     their mechanism — they construct mechanism-shaped Π for the generic
#     consumer; only the switch itself stays vocabulary-free.
#   - It performs NO isolation-flag reads: isolation is consumed at edge
#     CONSTRUCTION (corollary 2 — isolation is edge-absence). `assembleSubtree`
#     resolves the subtree boundary (via scope-walk.subtreeScopes, governed by
#     Π's EXPLICIT isolationMode) BEFORE handing merge edges to the switch, so
#     the switch only walks an already-bounded scope list.
{ lib, den, ... }:
let
  inherit (import ../scope-walk.nix { inherit lib; }) subtreeScopes dedupByKey;
  inherit (import ./default.nix { inherit lib; }) defaultFoldEdges;
  inherit (import ./pi.nix { inherit lib; }) mkStaticPi;
  inherit (import ./edge.nix { inherit lib; }) scopeName;
in
rec {
  # The Π(root) record shape (§A). Per-field comments note the invariant that
  # constrains each. The default-fold merge consumes only
  # perScope/scopeParent/scopeIsolated/rootScopeId/dedupMode/allScopeIds; the
  # remaining fields are the route/provides/spawn projection inputs (the variants
  # are visible data instead of implicit state-threading).
  #
  # Π(root) = {
  #   scopeContexts;          # §9 subtree-only context slice. NOT read by the
  #                           #   default-fold merge (which reads perScope buckets
  #                           #   directly); routes/provides/synthesize materialize
  #                           #   against it.
  #   contextsAreAugmented;   # §8 DELIBERATE (cycle-forced) — B′ gets raw contexts.
  #                           #   Carried so a unified assembleSubtree knows which it
  #                           #   got.
  #   classImports;           # (caller-merged: accumulator) §2 the collected class
  #                           #   buckets, per-scope (perScope). The default-fold merge
  #                           #   SOURCE. TARGET semantics = drained (the B′ baseDrain
  #                           #   divergence is fixed via the augmented-context build,
  #                           #   §A #8/#2/#7 option b).
  #   provides;               # (caller-merged: route/provides fold input, not static-Π)
  #                           #   §9 subtree+ancestors; §3 spawn's own suffices.
  #   routes;                 # (caller-merged: route/provides fold input, not static-Π)
  #                           #   §9 subtree+ancestors; §4 parent-subtree routes merge
  #                           #   into a spawn.
  #   rootScopeId;            # §5 DELIBERATE — the subtree root (pipeline root |
  #                           #   hostScopeId | spawnRoot). The merge target's root.
  #   scopeParent;            # the parent DAG slice (subtree/ancestor walks).
  #   scopeIsolated;          # §6/§10 — the isolation marks. Consulted at EXTRACTION
  #                           #   via subtreeScopes, governed by isolationMode; never
  #                           #   read inside the mode switch.
  #   isolationMode;          # §6 `aware` (default) | `blind` (spawn final extraction
  #                           #   invariant). EXPLICIT — never defaulted.
  #   dedupMode ? "dedup";    # the merge-mode collection dial. "dedup" (default) =
  #                           #   first-occurrence-wins cross-scope key dedup
  #                           #   (extractSubtreeModules / wrapPerScope semantics).
  #                           #   "raw" = dedup-FREE concat (the spawn final-extraction
  #                           #   invariant): the spawn's phase1 wrapPerScope
  #                           #   already key-deduped INTO the perScope buckets, and the
  #                           #   final per-scope concat must NOT re-dedup across scopes
  #                           #   (a duplicate cross-scope module is a deliberate keyless
  #                           #   re-emission the target's own evalModules reconciles).
  #   allScopeIds ? null;     # optional subtree-universe override. null ⇒ derive from
  #                           #   perScope attrnames (the entity-root/per-host re-entries).
  #                           #   The spawn re-entry passes mergedScopeParent ∪
  #                           #   scopedRoutes keys EXPLICITLY: a route-only scope can sit
  #                           #   on the subtree parent-chain without a perScope bucket, so
  #                           #   the membership universe is WIDER than perScope alone.
  #   classInject ? null;     # §1 the resolved entity class to inject into context
  #                           #   args; no observable witness — defensive projection,
  #                           #   default off.
  # }

  # Resolve Π's isolation marks into the `isolated` set the subtree walk takes,
  # governed by the EXPLICIT isolationMode (§A: "pass it EXPLICITLY, never by
  # defaulting"). blind ⇒ {} (the spawn final-extraction invariant); aware ⇒ the
  # scope isolation marks. This is the ONLY place an isolation mark is consulted,
  # and it happens at CONSTRUCTION (assembleSubtree), not inside the switch.
  isolatedSetOf =
    pi:
    if pi.isolationMode == "blind" then
      { }
    else if pi.isolationMode == "aware" then
      pi.scopeIsolated
    else
      throw "den materialize: isolationMode must be \"aware\" | \"blind\", got ${builtins.toJSON pi.isolationMode}";

  # Collect the merge source for a (root, class) target: the class bucket of the
  # already-bounded subtree. With dedupMode = "dedup" (default) this is the
  # wrapPerScope cross-scope dedup + extractSubtreeModules semantics (first-
  # occurrence-wins by key); with dedupMode = "raw" it is a dedup-FREE concat
  # (the spawn final-extraction invariant — phase1 already key-deduped into the
  # buckets, so a remaining cross-scope duplicate is a deliberate keyless
  # re-emission, not a dedup target).
  #   perScope        — sid → { class → [ modules ] } (the wrapped buckets).
  #   subtreeScopeIds — the resolved, isolation-bounded scope list.
  #   dedupMode       — "dedup" | "raw".
  collectMerge =
    perScope: subtreeScopeIds: dedupMode: cls:
    if dedupMode == "raw" then
      # Dedup-free: iterate the perScope buckets in perScope-attrname order
      # (the spawn final extraction's exact iteration), restricted to subtree
      # membership. Order is load-bearing without a key-dedup, so we walk
      # perScope keys directly rather than the allScopeIds-ordered subtree list.
      let
        member = lib.genAttrs subtreeScopeIds (_: true);
      in
      lib.concatMap (sid: perScope.${sid}.${cls} or [ ]) (
        builtins.filter (sid: member ? ${sid}) (builtins.attrNames perScope)
      )
    else
      dedupByKey (m: m.key or null) (lib.concatMap (sid: perScope.${sid}.${cls} or [ ]) subtreeScopeIds);

  # materialize: Π + an edge list → { class → [ modules ] }. The ONLY mode
  # switch for default-fold extraction. The merge arm here is the per-root final
  # extraction; routes + provides are interleaved upstream by the unified ordered-
  # dispatch fold (edges/materialize-unified.nix materializeUnified, the single
  # delivery engine for every site), which calls assembleSubtree for the final
  # merge — so `assembleSubtree` carries merge edges only. `perScope` and the
  # resolved subtree are passed via the closure `ctx`.
  materialize =
    pi: ctx: edges:
    let
      step =
        acc: edge:
        let
          cls = edge.target.class;
        in
        if edge.mode == "merge" then
          # merge: module-list union of the bounded subtree's bucket, deduped or
          # raw per ctx.dedupMode (the spawn final extraction is dedup-free).
          acc
          // {
            ${cls} = (acc.${cls} or [ ]) ++ collectMerge ctx.perScope ctx.subtreeScopeIds ctx.dedupMode cls;
          }
        else
          throw "den materialize: assembleSubtree edge mode ${builtins.toJSON edge.mode} (nest/nest-verbatim route delivery folds through edges/route.nix:materializeRouteEdge, not assembleSubtree)";
    in
    builtins.foldl' step { } edges;

  # assembleSubtree: materialize all edges targeting `root`. For the default-fold
  # port this is the per-root final extraction that replaces extractSubtreeModules
  # — the merge-mode materialization of the root's own default-fold edges.
  #
  # The subtree boundary (isolation) is resolved HERE (construction time,
  # corollary 2), producing the bounded scope list the merge switch walks. The
  # mode switch never sees an isolation flag.
  #
  #   root  — the root scope id whose content is being assembled.
  #   pi    — the Π(root) projection (shape above).
  # Returns { class → [ modules ] }; a class with no content is absent (callers
  # treat absence as null, matching extractSubtreeModules' `== [] then null`).
  assembleSubtree =
    { root, pi }:
    let
      # The subtree-membership universe. Default = perScope attrnames (the entity-
      # root / per-host re-entries). The spawn re-entry passes pi.allScopeIds
      # explicitly (mergedScopeParent ∪ scopedRoutes keys) because a route-only
      # scope can sit on the subtree parent-chain without a perScope bucket.
      allScopeIds = pi.allScopeIds or (builtins.attrNames pi.perScope);
      # The merge collection dial (§A spawn invariant): default dedup; "raw" =
      # dedup-free concat (spawn final extraction).
      dedupMode = pi.dedupMode or "dedup";
      # The isolation set the subtree boundary uses, governed by pi.isolationMode.
      # Computed ONCE here so the merge-collection walk and the edge constructor's
      # own internal subtree walk agree on the boundary.
      isolated = isolatedSetOf pi;
      subtreeScopeIds = subtreeScopes {
        inherit (pi) scopeParent;
        inherit isolated root allScopeIds;
      };
      # Default-fold edges for THIS root, built by the SHARED constructor
      # (edges/default.nix defaultFoldEdges) — the same function the read-only
      # oracle (edge-trace.nix) consumes, so production and oracle agree on the
      # CONSTRUCTOR, not merely the primitives (spec §3a convergence).
      # Adaptation to assembleSubtree's per-root, isolationMode-governed call:
      #   - entityRootScopes = [ root ] (this single root; isolated descendants
      #     are their own roots, materialized by their own assembleSubtree).
      #   - scopeIsolated = `isolated` (already resolved through isolationMode, so
      #     the constructor's internal subtree walk matches subtreeScopeIds).
      #   - classContentAt = pi.perScope (only `? class` membership is read).
      #   - name = identity: the merge switch reads ONLY edge.target.class, so the
      #     T.root naming used by the oracle is irrelevant here; identity keeps the
      #     emitted target.root = the raw sid, unchanged from the prior inline form.
      edges = defaultFoldEdges {
        name = sid: sid;
        inherit (pi) scopeParent;
        scopeIsolated = isolated;
        classContentAt = pi.perScope;
        inherit allScopeIds;
        entityRootScopes = [ root ];
      };
    in
    materialize pi {
      inherit (pi) perScope;
      inherit subtreeScopeIds dedupMode;
    } edges;

  # assembleSpawnSubtree: the spawn node's full phase-fold + final extraction,
  # expressed over the edge machinery. The spawn's inline
  # phase1(wrapPerScope) → phase2(applyProvides) → phase3(applyRoutes) →
  # isolation-BLIND dedup-FREE subtree concat is reproduced here as ONE entry:
  # the phase fold builds the perScope buckets, then `assembleSubtree` performs
  # the final per-root extraction with the spawn's two distinguishing dials —
  # `isolationMode = "blind"` (documented invariant: no isolated
  # descendant can appear under a spawnRoot, since isolated kinds are created by
  # resolve.to in the HOST pipeline, never via spawnNode) and `dedupMode = "raw"`
  # (the phase1 wrapPerScope already key-deduped INTO the buckets; the final
  # cross-scope concat must NOT re-dedup — a remaining duplicate is a deliberate
  # keyless re-emission the target's own evalModules reconciles).
  #
  # The phase primitives are passed IN (wrapPerScope), so this helper introduces no
  # resolve.nix import — the spawn keeps its existing injection seam; only the
  # inline phase-1 CALL expression moves here (provides + routes now fold through
  # materializeUnified, not injected applyProvides/applyRoutes primitives).
  #
  #   class                 — the single class this spawn node materializes.
  #   spawnRoot             — the spawn subtree root.
  #   ctx                   — the pipeline base ctx (phase fallback context).
  #   augmented             — the spawn's assemblePipes-augmented contexts.
  #   mergedClassImports    — phase1 source (parent + spawned, pipe-stripped).
  #   mergedScopeParent     — the merged parent DAG (spawnRoot linked up to host).
  #   mergedScopeIsolated   — merged isolation marks (inert under blind mode).
  #   ownProvides           — the spawn's OWN provides (parent provides are
  #                           deliberately NOT reapplied).
  #   mergedSpawnRoutes     — parent-subtree routes (routeKey-deduped) ⊕ spawn own
  #                           (parent routes MUST merge into the spawn).
  #   allScopeIds           — the subtree-membership universe (mergedScopeParent ∪
  #                           scopedRoutes keys — WIDER than perScope alone).
  #   selfRef               — the spawn primitive (nested-forward resolver).
  #   wrapPerScope          — the injected phase-1 wrap primitive.
  assembleSpawnSubtree =
    {
      class,
      spawnRoot,
      ctx,
      augmented,
      scopeEntityKind,
      ownEntityOf,
      mergedClassImports,
      mergedScopeParent,
      mergedScopeIsolated,
      ownProvides,
      mergedSpawnRoutes,
      allScopeIds,
      selfRef,
      wrapPerScope,
    }:
    let
      phase1 = wrapPerScope ctx augmented mergedClassImports;
      # Production delivery (Task 17/18): the spawn final extraction folds
      # materializeUnified (doFinalMerge = true → it runs assembleSubtree at
      # spawnRoot), replacing the phase2 (provides) ∘ phase3 (routes) ∘
      # assembleSubtree sequence. exposeAcc surfaces the post-fold accumulator so
      # the `edges` collector reads its perScope from the SAME fold — there is no
      # separate phase2∘phase3 fold to diverge from. The Π keeps the spawn's two
      # distinguishing dials — isolationMode = "blind" + dedupMode = "raw" — and the
      # EXPLICIT allScopeIds subtree-universe override. scopeContexts = augmented is
      # the SAME contexts the complex-forward path reads for source resolution.
      piUnified =
        (mkStaticPi {
          rootScopeId = spawnRoot;
          scopeContexts = augmented;
          scopeParent = mergedScopeParent;
          scopeIsolated = mergedScopeIsolated;
          isolationMode = "blind";
          dedupMode = "raw";
          inherit allScopeIds;
        })
        // {
          inherit scopeEntityKind ownEntityOf;
        };
      # materializeUnified is reached via the lazy `den` namespace (NOT a direct
      # import) — materialize-unified.nix imports THIS file for assembleSubtree, so
      # a direct import would cycle. Nix laziness makes the namespace access fine.
      materialized =
        den.lib.aspects.fx.edges.materializeUnified.materializeUnified
          {
            pi = piUnified;
            inherit ctx;
            seed = phase1;
            scopedProvides = ownProvides;
            scopedRoutes = mergedSpawnRoutes;
            spawnNode = selfRef;
            buildForwardAspect = den.lib.aspects.fx.handlers.buildForwardAspect;
          }
          {
            doFinalMerge = true;
            exposeAcc = true;
            # Task 18.2: CAPTURE the provides+routes edges the fold dispatched
            # (materialized.edges), instead of re-deriving them below via
            # providesEdges/routeEdges. The default-fold edge stays constructor-
            # built (deterministic structural edge, not a drift surface).
            exposeEdges = true;
          };
      # Π used by the `edges` collector's isolation-set resolution (blind ⇒ {}).
      pi = piUnified;
      # The SURFACED edge set for THIS spawn node — the spawn's default-fold merge
      # edge(s) (built here via the shared defaultFoldEdges constructor) ++ the
      # spawn's provides + re-applied mergedSpawnRoutes route edges (CAPTURED from
      # the materializeUnified fold below, Task 18.2). `.imports` consumers read only
      # imports; `.edges` is now consumed by the production `edgeTrace` (resolve.nix)
      # — it is the spawn's contribution to the captured production edge object.
      #
      # DELIBERATE name-space note: assembleSubtree's INTERNAL defaultFoldEdges
      # uses `name = sid: sid` (identity) because the merge switch reads only
      # `edge.target.class`. The SURFACED edges here use `scopeName`
      # (`<kind>:<id_hash>`) to match the oracle/unified-set normalization. These
      # two name spaces are intentionally DIFFERENT — do NOT unify them.
      name = scopeName {
        inherit scopeEntityKind;
        scopeContexts = augmented;
      };
      edges =
        (defaultFoldEdges {
          inherit name;
          scopeParent = mergedScopeParent;
          scopeIsolated = isolatedSetOf pi; # blind ⇒ {} — matches the merge boundary
          classContentAt = materialized.acc.perScope;
          inherit allScopeIds;
          entityRootScopes = [ spawnRoot ];
        })
        # Task 18.2: the provides+routes edges are the CAPTURE from the SAME
        # materializeUnified fold above (materialized.edges), not a re-derivation
        # via providesEdges/routeEdges — so the surfaced set can never drift from
        # what the fold actually dispatched.
        ++ materialized.edges;
    in
    {
      imports = materialized.merged.${class} or [ ];
      inherit edges;
    };
}
