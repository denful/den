# materialize-unified.nix — the ordered-dispatch delivery engine (Task 17).
#
# It REPLACED phase folds, and they are gone: phase2 applied ALL provides
# (edges/provides.nix `applyProvidesEdges`), THEN phase3 applied ALL routes
# (edges/route.nix `applyRoutes`, which itself toposorted its route specs),
# threading an accumulator `{ classImports; perScope }` through both. Neither
# function still exists; the shape is described here only because the ordering
# argument below is stated against it.
#
# materializeUnified collapses that into ONE ordered-dispatch fold that INTERLEAVES
# provides + routes in `topoSortEdges` order, reusing the EXISTING per-spec
# materializers (provides.applyOneProvide | route.applySimpleRouteEdge |
# route.applyComplexRouteEdge). It is order-only (Design B): because
#
#   - provides currently always precede routes, and
#   - the unified edge list is built `provides-edges ++ route-edges` and run
#     through a STABLE topoSortEdges (toposort.nix lock-in: independents keep
#     input order),
#
# independent edges keep the provides-before-routes order → byte-identical to
# phase2∘phase3; the only dependent edges (synthesize / complex forwards) land
# AFTER their producers exactly as applyRoutes' own internal toposort already
# orders them. The final-extraction merge stays the existing assembleSubtree step
# (only when doFinalMerge), unchanged.
#
# This engine IS production delivery at every site as of Task 17 (fxResolveFull,
# fxResolveImports, the per-host re-walk, and the spawn re-entry all fold it). It
# was proven byte-equivalent to the old phase2∘phase3 (+ optional assembleSubtree)
# by the fx-materialize-unified suite and its materializeEquiv oracle. Both were
# retired with the phase folds, so that equivalence is history rather than a
# standing comparison. Its `exposeEdges` mode (Task 18) returns the
# folded provides+routes edge records so the production `edgeTrace` is captured,
# not re-derived.
{ lib, den }:
let
  routeEdgesMod = import ./route.nix { inherit lib den; };
  providesMod = import ./provides.nix { inherit lib den; };
  inherit (import ./materialize.nix { inherit lib den; }) assembleSubtree;
  inherit (import ./toposort.nix { inherit lib; }) topoSortEdges;

  inherit (routeEdgesMod)
    applyComplexRouteEdge
    applySimpleRouteEdge
    orderedKeptRoutes
    routeEdges
    ;
  inherit (providesMod)
    applyOneProvide
    dedupProvides
    providesEdges
    ;

  # materializeUnified: ONE ordered-dispatch fold over the unified provides+routes
  # edge set, byte-equivalent to phase2∘phase3 (+ optional assembleSubtree).
  #
  #   pi             — the Π(root) record (rootScopeId + the static slice). Read for
  #                    the optional final merge (assembleSubtree) and rootScopeId.
  #   seed           — phase-1 output { classImports; perScope } (the fold start).
  #   ctx            — the pipeline base ctx (provides wrap context).
  #   scopedProvides — sid → [ provide specs ] (phase-2 input).
  #   scopedRoutes   — sid → [ route specs ] (phase-3 input).
  #   spawnNode      — the threaded node-spawn primitive (complex-forward source).
  #   buildForwardAspect — the synthesize constructor (handlers/forward.nix).
  #   doFinalMerge   — true ⇒ return assembleSubtree { root; pi // acc }; false ⇒
  #                    return the raw accumulator (caller reads classImports).
  #   exposeAcc      — with doFinalMerge = true, return BOTH the merged output AND
  #                    the post-provides+routes accumulator from the SAME fold:
  #                    `{ merged = <doFinalMerge result>; acc = <{classImports;perScope}>; }`.
  #                    Lets the per-host / spawn edge collectors source the class-
  #                    content presence map (acc.perScope) WITHOUT a second
  #                    phase2∘phase3 fold (it replaced the old phase3.perScope).
  materializeUnified =
    {
      pi,
      seed,
      ctx,
      scopedProvides,
      scopedRoutes,
      spawnNode,
      buildForwardAspect,
    }:
    {
      doFinalMerge ? false,
      # When set, return the ORDERED dispatch sequence [ { kind; spec } ] instead of
      # the materialized accumulator — the Task-17 equivalence proof compares this to
      # the production phase2∘phase3 dispatch order (the load-bearing Design-B claim).
      exposeDispatch ? false,
      # With doFinalMerge, also expose the post-fold accumulator (the edge
      # collectors' content source). See the option doc above.
      exposeAcc ? false,
      # When set, ALSO carry the folded edge records — `map (p: p.edge)
      # orderedPairs`, i.e. the SAME trace edges this fold dispatched, in fold
      # (post-toposort) order. The literal-object trace capture primitive
      # (Task 18). Composes with the doFinalMerge / exposeAcc return path (does
      # NOT route through the early exposeDispatch return), so spawn / per-host
      # sites can take `merged` + `acc` + `edges` together.
      #
      # Return-shape table (doFinalMerge, exposeAcc, exposeEdges) → shape:
      #   exposeDispatch = true (any flags)  → [ { kind; spec } ]   (early; unaffected)
      #   (false, _,     false)              → acc
      #   (false, _,     true )              → acc // { edges; }
      #   (true,  false, false)              → merged                (bare attrset)
      #   (true,  false, true )              → { merged; edges; }
      #   (true,  true,  false)              → { merged; acc; }
      #   (true,  true,  true )              → { merged; acc; edges; }
      # The exposeEdges = false rows are byte-identical to the pre-Task-18
      # returns: every existing caller (none pass exposeEdges) is unchanged.
      exposeEdges ? false,
    }:
    let
      inherit (pi)
        rootScopeId
        scopeContexts
        scopeParent
        scopeIsolated
        scopeEntityKind
        ;
      # Stable scope name for the trace-edge construction (ordering only).
      name = den.lib.aspects.fx.edges.edge.scopeName {
        scopeEntityKind = pi.scopeEntityKind or { };
        inherit scopeContexts;
      };

      # ===== 1. The unified producer-edge SPEC list, phase order ============
      # Provides FIRST (deduped, in dedupProvides order — phase2), routes SECOND
      # (kept + toposorted, in orderedKeptRoutes order — phase3). Each spec is
      # paired with its TRACE edge for the unified toposort (the trace edges carry
      # the cell-model identity topoSortEdges reads; the SPEC drives materialization).

      dedupedProvides = dedupProvides (lib.concatLists (lib.attrValues scopedProvides));
      providesTraceEdges = providesEdges {
        inherit name;
        inherit scopedProvides;
      };
      # providesEdges dedups internally with the SAME dedupProvides, so the trace
      # edge list aligns 1:1 with dedupedProvides (same order, same count).
      providesPairs = lib.zipListsWith (spec: edge: {
        kind = "provide";
        inherit spec edge;
      }) dedupedProvides providesTraceEdges;

      orderedRoutes = orderedKeptRoutes rootScopeId (lib.concatLists (lib.attrValues scopedRoutes));
      # Build the matching trace edges over the SAME kept+ordered route list, so
      # the spec↔edge pairing is 1:1 and in the same order applyRoutes folds.
      routeTraceEdges = routeEdges {
        inherit name scopeParent rootScopeId;
        rawRoutes = orderedRoutes;
      };
      routePairs = lib.zipListsWith (spec: edge: {
        kind = "route";
        inherit spec edge;
      }) orderedRoutes routeTraceEdges;

      pairs = providesPairs ++ routePairs;

      # ===== 2. STABLE toposort over the paired trace edges =================
      # Independents keep input order (provides-before-routes); synthesize edges
      # land after the producers of their fromClass (the cell model). topoSortEdges
      # returns reordered edge RECORDS, so we tag each edge with its source pair
      # index (inert — the cell model reads target/source/mode/annotations only) and
      # index the pairs back out after the sort.
      taggedEdges = lib.imap0 (i: p: p.edge // { __pairIdx = i; }) pairs;
      sortedTagged = topoSortEdges taggedEdges;
      orderedPairs = map (e: builtins.elemAt pairs e.__pairIdx) sortedTagged;

      # ===== 3. The interleaved ordered-dispatch fold ======================
      # acc = { classImports; perScope }. Simple routes read the FROZEN phase-1
      # perScope (seed.perScope), NOT the evolving acc — matching applyRoutes,
      # whose route fold's `wrappedPerScope` is captured ONCE at fold start. Complex
      # forwards read the EVOLVING acc (getCollectedSource reads acc.perScope).
      wrappedPerScope = seed.perScope;
      acc = builtins.foldl' (
        prev: pair:
        if pair.kind == "provide" then
          applyOneProvide ctx prev pair.spec
        else if pair.spec.__complexForward or false then
          applyComplexRouteEdge prev {
            route = pair.spec;
            inherit
              rootScopeId
              scopeContexts
              scopeParent
              scopeEntityKind
              spawnNode
              buildForwardAspect
              ;
          }
        else
          applySimpleRouteEdge prev {
            route = pair.spec;
            inherit wrappedPerScope scopeParent scopeIsolated;
          }
      ) seed orderedPairs;

      # The folded edge records, in fold (post-toposort) order — the exact trace
      # edges the dispatch above consumed. Captured for the literal-object trace.
      foldedEdges = map (p: p.edge) orderedPairs;
    in
    if exposeDispatch then
      map (p: {
        inherit (p) kind spec;
      }) orderedPairs
    else if doFinalMerge then
      let
        merged = assembleSubtree {
          root = rootScopeId;
          pi = pi // acc;
        };
      in
      if exposeAcc then
        { inherit merged acc; } // lib.optionalAttrs exposeEdges { edges = foldedEdges; }
      else if exposeEdges then
        {
          inherit merged;
          edges = foldedEdges;
        }
      else
        merged
    else if exposeEdges then
      acc // { edges = foldedEdges; }
    else
      acc;
in
{
  inherit materializeUnified;
}
