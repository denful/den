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
    targetScopeOf
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
      inherit (pi) ownEntityOf;
      # Nesting moves no content: every scope with an own entity bounds the
      # walks that assemble class content (the default fold, collectSubtree
      # routes). The kind-level isolation marks stay in the set (the
      # deprecated `isolated` alias). The walk's root is always included.
      # A scope binding a user its host accepts through user-aspects (the
      # user's own, or an entity resolved for that user) is not a boundary: its
      # content reaches the host as on main.
      acceptedUserScope =
        sid:
        let
          ctx = scopeContexts.${sid} or { };
        in
        ctx ? host
        && ctx ? user
        && (ctx.home or null) == null
        && ownEntityOf.${sid} != (ctx.host.id_hash or null)
        && den.lib.acceptance.accepts ctx ctx.host ctx.user;
      entityBoundary =
        scopeIsolated
        // lib.mapAttrs (_: _: true) (lib.filterAttrs (sid: _: !(acceptedUserScope sid)) ownEntityOf);
      rootCtx = scopeContexts.${rootScopeId} or { };
      outerEntities = lib.listToAttrs (
        map (r: lib.nameValuePair r.id_hash true) (
          builtins.filter (
            r: builtins.isAttrs r && r ? id_hash && r.id_hash != (ownEntityOf.${rootScopeId} or null)
          ) (builtins.attrValues rootCtx)
        )
      );
      targetOf = targetScopeOf { inherit scopeParent ownEntityOf outerEntities; };
      # A delivery to an entity this resolve does not build has no target here.
      landsHere = spec: targetOf spec != null;
      liveProvides = lib.mapAttrs (_: builtins.filter landsHere) scopedProvides;
      liveRoutes = lib.mapAttrs (_: builtins.filter landsHere) scopedRoutes;
      # A scope with no own entity belongs to its nearest entity ancestor (a
      # microvm guest, a routing scope); a chain with none keys on the scope.
      entityOf =
        sid:
        let
          go =
            s:
            if ownEntityOf ? ${s} then
              ownEntityOf.${s}
            else
              let
                p = scopeParent.${s} or null;
              in
              if p == null || p == s then sid else go p;
        in
        go sid;
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

      dedupedProvides = dedupProvides entityOf (lib.concatLists (lib.attrValues liveProvides));
      providesTraceEdges = providesEdges {
        inherit name entityOf targetOf;
        scopedProvides = liveProvides;
      };
      # providesEdges dedups internally with the SAME dedupProvides, so the trace
      # edge list aligns 1:1 with dedupedProvides (same order, same count).
      providesPairs = lib.zipListsWith (spec: edge: {
        kind = "provide";
        inherit spec edge;
      }) dedupedProvides providesTraceEdges;

      orderedRoutes = orderedKeptRoutes targetOf rootScopeId (
        lib.concatLists (lib.attrValues liveRoutes)
      );
      # Build the matching trace edges over the SAME kept+ordered route list, so
      # the spec↔edge pairing is 1:1 and in the same order applyRoutes folds.
      routeTraceEdges = routeEdges {
        inherit
          name
          scopeParent
          rootScopeId
          targetOf
          ;
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
      # A simple route reads the frozen seed, unless a delivery writes into a
      # bucket it reads: then it reads that bucket after the fold, pinned after
      # every producer into it (keyed by the producer's target, so a `receiver`
      # delivery counts where it lands). A collectSubtree route always reads
      # the folded subtree: a delivered guest carries its users' deliveries
      # (#742).
      pairIdxs = lib.range 0 (builtins.length pairs - 1);
      classOfPair = p: if p.kind == "provide" then p.spec.class else p.spec.intoClass;
      producerIdxs = builtins.foldl' (
        acc: i:
        let
          p = builtins.elemAt pairs i;
          key = "${classOfPair p}@${targetOf p.spec}";
        in
        if p.kind == "route" && isClassAlias p.spec then
          acc
        else
          acc // { ${key} = (acc.${key} or [ ]) ++ [ i ]; }
      ) { } pairIdxs;
      producerScopes = lib.unique (
        map (i: targetOf (builtins.elemAt pairs i).spec) (
          builtins.filter (
            i:
            let
              p = builtins.elemAt pairs i;
            in
            !(p.kind == "route" && isClassAlias p.spec)
          ) pairIdxs
        )
      );
      readScopesOf =
        r:
        if (r.collectSubtree or false) || r.intoClass == "flake" then
          subtreeScopes {
            inherit scopeParent;
            isolated = if r.intoClass == "flake" then scopeIsolated else entityBoundary;
            root = r.sourceScopeId;
            allScopeIds = producerScopes;
          }
        else
          [ r.sourceScopeId ];
      deliveryDepsOf =
        i: r:
        builtins.filter (j: j != i) (
          lib.concatMap (sid: producerIdxs."${r.fromClass}@${sid}" or [ ]) (readScopesOf r)
        );
      isSimpleReader =
        p: p.kind == "route" && !(p.spec.__complexForward or false) && !(isClassAlias p.spec);
      readerDeps = lib.imap0 (i: p: if isSimpleReader p then deliveryDepsOf i p.spec else [ ]) pairs;
      readsDelivered =
        i: (builtins.elemAt readerDeps i) != [ ] || (builtins.elemAt pairs i).spec.collectSubtree or false;
      taggedEdges = lib.imap0 (
        i: p:
        p.edge
        // {
          __pairIdx = i;
        }
        // lib.optionalAttrs (readerDeps' i != [ ]) {
          __afterEdges = readerDeps' i;
        }
      ) pairs;
      readerDeps' = i: builtins.elemAt readerDeps i;
      sortedTagged = topoSortEdges taggedEdges;
      orderedPairs = map (
        e: (builtins.elemAt pairs e.__pairIdx) // { __idx = e.__pairIdx; }
      ) sortedTagged;

      # ===== 3. The interleaved ordered-dispatch fold ======================
      # acc = { classImports; perScope }. Simple routes read the FROZEN phase-1
      # perScope (seed.perScope), NOT the evolving acc, unless they read a
      # delivered bucket (above): those read the seed plus every delivery
      # appended so far (`delivered`, keyed by target). Complex forwards read the
      # EVOLVING acc (getCollectedSource reads acc.perScope).
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
        && (r.receiver or null) == null
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

      withDelivered =
        delivered:
        builtins.foldl' (
          perScope: sid:
          builtins.foldl' (ps: cls: appendAt ps sid cls delivered.${sid}.${cls}) perScope (
            builtins.attrNames delivered.${sid}
          )
        ) aliasedPerScope (builtins.attrNames delivered);

      # Each step only appends to its target bucket, so what it delivered is the
      # new suffix there.
      recordDelivery =
        prev: next: sid: cls:
        let
          before = prev.acc.perScope.${sid}.${cls} or [ ];
          added = lib.drop (builtins.length before) (next.perScope.${sid}.${cls} or [ ]);
        in
        {
          acc = next;
          delivered = if added == [ ] then prev.delivered else appendAt prev.delivered sid cls added;
        };

      folded =
        builtins.foldl'
          (
            prev: pair:
            let
              inherit (pair) spec;
              target = targetOf spec;
            in
            if pair.kind == "provide" then
              recordDelivery prev (applyOneProvide targetOf ctx prev.acc spec) target spec.class
            else if spec.__complexForward or false then
              recordDelivery prev (applyComplexRouteEdge prev.acc {
                route = spec;
                inherit
                  rootScopeId
                  scopeContexts
                  scopeParent
                  scopeEntityKind
                  spawnNode
                  buildForwardAspect
                  targetOf
                  ;
              }) target spec.intoClass
            else
              let
                next = applySimpleRouteEdge prev.acc {
                  route = spec;
                  wrappedPerScope =
                    if isClassAlias spec then
                      wrappedPerScope
                    else if readsDelivered pair.__idx then
                      withDelivered prev.delivered
                    else
                      aliasedPerScope;
                  inherit
                    scopeParent
                    scopeIsolated
                    entityBoundary
                    targetOf
                    ;
                  provenanceLocs = pi.provenanceLocs or { };
                };
              in
              if isClassAlias spec then
                prev // { acc = next; }
              else
                recordDelivery prev next target spec.intoClass
          )
          {
            acc = seed;
            delivered = { };
          }
          orderedPairs;
      inherit (folded) acc;

      # TODO(#694): the loss check, removed 30 days after the release that
      # bounds the merge. For class `cls`: content in a nested entity's bucket
      # that no delivery carries to the root. Each entry is
      # { scope; entity; aspect; }.
      lostAt =
        cls:
        let
          isolatedOnly = subtreeScopes {
            inherit scopeParent;
            isolated = scopeIsolated;
            root = rootScopeId;
            allScopeIds = builtins.attrNames acc.perScope;
          };
          boundedSet = lib.genAttrs (subtreeScopes {
            inherit scopeParent;
            isolated = entityBoundary;
            root = rootScopeId;
            allScopeIds = builtins.attrNames acc.perScope;
          }) (_: true);
          nested = builtins.filter (sid: !(boundedSet ? ${sid})) isolatedOnly;
          # A scope whose `cls` bucket a receiver route moves on whole is read.
          # A provenance route (mutual-provider) reads only the locations
          # emitted under its provider.
          receiverRoutes = builtins.filter (
            p: p.kind == "route" && (p.spec.receiver or null) != null && p.spec.fromClass == cls
          ) orderedPairs;
          readScopes = lib.genAttrs (map (p: p.spec.sourceScopeId) (
            builtins.filter (p: (p.spec.__fromProvenance or null) == null) receiverRoutes
          )) (_: true);
          provenanceRead = lib.genAttrs (lib.concatMap (
            p:
            map (l: "${p.spec.sourceScopeId}\n${den.lib.aspects.fx.identity.stripCtxSuffix l}") (
              ((pi.provenanceLocs or { }).${p.spec.sourceScopeId} or { }).${p.spec.__fromProvenance} or [ ]
            )
          ) (builtins.filter (p: (p.spec.__fromProvenance or null) != null) receiverRoutes)) (_: true);
          # An identity is rooted at the entity it was walked under
          # (`user/<anon>:6` at a user scope, `host/<anon>:6` at the host for the
          # same `den.default` include), so the leading entity-kind segment is
          # dropped before comparing.
          entityKinds = lib.genAttrs den.lib.schemaUtil.schemaEntityKinds (_: true);
          dropKindRoot =
            id:
            let
              segs = lib.splitString "/" id;
            in
            if builtins.length segs > 1 && entityKinds ? ${builtins.head segs} then
              lib.concatStringsSep "/" (builtins.tail segs)
            else
              id;
          identityOf =
            m:
            let
              raw = toString (m.key or m._file or "");
              noClass = lib.removePrefix "${cls}@" raw;
            in
            if raw == "" then null else dropKindRoot (den.lib.aspects.fx.identity.stripCtxSuffix noClass);
          rootMods = bounded.${cls} or [ ];
          # A module's keys, its own and those of the attrset modules it
          # imports: an anonymous wrapper around a keyed module (the
          # home-manager host-module import) is the keyed module.
          keysOf =
            m:
            if !builtins.isAttrs m then
              [ ]
            else
              lib.optional (m ? key) (toString m.key) ++ lib.concatMap keysOf (m.imports or [ ]);
          rootKeys = lib.genAttrs (lib.concatMap keysOf rootMods) (_: true);
          rootIds = lib.genAttrs (builtins.filter (i: i != null) (map identityOf rootMods)) (_: true);
          reachesRoot =
            m:
            let
              id = identityOf m;
            in
            (
              let
                ks = keysOf m;
              in
              ks != [ ] && builtins.all (k: rootKeys ? ${k}) ks
            )
            || (id != null && rootIds ? ${id});
          entityOf = sid: (scopeContexts.${sid} or { }).${scopeEntityKind.${sid} or ""} or null;
        in
        lib.concatMap (
          sid:
          map
            (m: {
              scope = sid;
              entity = (entityOf sid).name or sid;
              aspect = identityOf m;
            })
            (
              builtins.filter (
                m:
                !(reachesRoot m)
                && !(
                  provenanceRead
                  ? "${sid}\n${den.lib.aspects.fx.identity.stripCtxSuffix (toString (m.key or m._file or ""))}"
                )
              ) (acc.perScope.${sid}.${cls} or [ ])
            )
        ) (builtins.filter (sid: !(readScopes ? ${sid})) nested);
      # The root's class content: its own bounded subtree after delivery. An
      # "aware" walk takes the entity boundary; a "blind" one (spawn extraction)
      # is unchanged.
      bounded = assembleSubtree {
        root = rootScopeId;
        pi =
          pi
          // acc
          // lib.optionalAttrs (pi.isolationMode == "aware" && !(pi.unboundedCollect or false)) {
            scopeIsolated = entityBoundary;
          };
      };

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
        merged = bounded // {
          __lostAt = lostAt;
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
    # The flat surface (den.lib.aspects.resolve, __resolveResult.imports) is the
    # root's bounded subtree too, so it agrees with the per-host merge.
    else if exposeEdges then
      acc
      // {
        classImports = bounded;
        __lostAt = lostAt;
      }
      // {
        edges = foldedEdges;
      }
    else
      acc
      // {
        classImports = bounded;
        __lostAt = lostAt;
      };
in
{
  inherit materializeUnified;
}
