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
  inherit (import ../scope-walk.nix { inherit lib; }) subtreeScopes;

  appendAt =
    perScope: sid: cls: mods:
    perScope
    // {
      ${sid} = (perScope.${sid} or { }) // {
        ${cls} = (perScope.${sid}.${cls} or [ ]) ++ mods;
      };
    };

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
      #
      # A collectSubtree simple route also reads what complex forwards append to
      # its subtree (see the fold below), a read the trace edge cannot show, so
      # it is pinned after those forwards by pair index.
      readsForwards = r: !(r.__complexForward or false) && (r.collectSubtree or false);
      forwardIdxs = builtins.filter (i: (builtins.elemAt pairs i).spec.__complexForward or false) (
        lib.range 0 (builtins.length pairs - 1)
      );
      forwardDepsOf =
        r:
        let
          sids = subtreeScopes {
            inherit scopeParent;
            isolated = scopeIsolated;
            root = r.sourceScopeId;
            allScopeIds = lib.unique (map (i: (builtins.elemAt pairs i).spec.sourceScopeId) forwardIdxs);
          };
        in
        builtins.filter (
          i:
          let
            f = (builtins.elemAt pairs i).spec;
          in
          f.intoClass == r.fromClass && builtins.elem f.sourceScopeId sids
        ) forwardIdxs;
      taggedEdges = lib.imap0 (
        i: p:
        p.edge
        // {
          __pairIdx = i;
        }
        // lib.optionalAttrs (p.kind == "route" && readsForwards p.spec) {
          __afterEdges = forwardDepsOf p.spec;
        }
      ) pairs;
      sortedTagged = topoSortEdges taggedEdges;
      orderedPairs = map (e: builtins.elemAt pairs e.__pairIdx) sortedTagged;

      # ===== 3. The interleaved ordered-dispatch fold ======================
      # acc = { classImports; perScope }. Simple routes read the FROZEN phase-1
      # perScope (seed.perScope), NOT the evolving acc — matching applyRoutes,
      # whose route fold's `wrappedPerScope` is captured ONCE at fold start. Complex
      # forwards read the EVOLVING acc (getCollectedSource reads acc.perScope).
      # A collectSubtree route additionally sees what complex forwards appended
      # (`forwarded`): a delivered guest must carry its home-manager users (#742).
      wrappedPerScope = seed.perScope;

      # A class alias is a simple route that only re-labels a class within its own
      # scope (`os-to-host`: os → nixos at path [] in place). Its output belongs to
      # the target class, so every OTHER simple route reading that class at that
      # scope must see it. Otherwise a route that collects `nixos` (e.g. a guest's
      # delivery) silently drops everything authored in `os`. Aliases themselves
      # keep reading the original data, so none can read its own output.
      isClassAlias =
        r:
        !(r.__complexForward or false)
        && (r.path or [ ]) == [ ]
        && !(r.collectSubtree or false)
        && !(r.appendToParent or false)
        && !(r.reinstantiate or false)
        && (r.instantiate or null) == null
        && (r.adapterKey or null) == null
        && (r.adapterModule or null) == null
        && (r.guard or null) == null
        && r.intoClass != "flake"
        && r.intoClass != r.fromClass;
      aliasedPerScope = builtins.foldl' (
        perScope: r:
        let
          aliased = wrappedPerScope.${r.sourceScopeId}.${r.fromClass} or [ ];
        in
        if aliased == [ ] then perScope else appendAt perScope r.sourceScopeId r.intoClass aliased
      ) wrappedPerScope (builtins.filter isClassAlias orderedRoutes);

      withForwarded =
        forwarded:
        builtins.foldl' (
          perScope: sid:
          builtins.foldl' (ps: cls: appendAt ps sid cls forwarded.${sid}.${cls}) perScope (
            builtins.attrNames forwarded.${sid}
          )
        ) aliasedPerScope (builtins.attrNames forwarded);

      folded =
        builtins.foldl'
          (
            prev: pair:
            if pair.kind == "provide" then
              prev // { acc = applyOneProvide ctx prev.acc pair.spec; }
            else if pair.spec.__complexForward or false then
              let
                inherit (pair.spec) sourceScopeId intoClass;
                next = applyComplexRouteEdge prev.acc {
                  route = pair.spec;
                  inherit
                    rootScopeId
                    scopeContexts
                    scopeParent
                    scopeEntityKind
                    spawnNode
                    buildForwardAspect
                    ;
                };
                before = prev.acc.perScope.${sourceScopeId}.${intoClass} or [ ];
                # applyComplexRouteEdge only appends, so its output is the new suffix.
                added = lib.drop (builtins.length before) next.perScope.${sourceScopeId}.${intoClass};
              in
              {
                acc = next;
                forwarded = appendAt prev.forwarded sourceScopeId intoClass added;
              }
            else
              prev
              // {
                acc = applySimpleRouteEdge prev.acc {
                  route = pair.spec;
                  wrappedPerScope =
                    if isClassAlias pair.spec then
                      wrappedPerScope
                    else if readsForwards pair.spec then
                      withForwarded prev.forwarded
                    else
                      aliasedPerScope;
                  inherit scopeParent scopeIsolated;
                };
              }
          )
          {
            acc = seed;
            forwarded = { };
          }
          orderedPairs;
      inherit (folded) acc;

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
