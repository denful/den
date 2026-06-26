# Post-pipeline assembly: provides → routes → instantiates → output.
# Transforms raw pipeline state into final { imports = [...]; }.
{
  lib,
  den,
  ...
}:
let
  inherit (import ./wrap-classes.nix { inherit lib den; }) wrapCollectedClasses;
  inherit (import ./assemble-pipes.nix { inherit lib den; }) assemblePipes;
  inherit (import ./spawn-node.nix { inherit lib den; }) mkSpawnNode;
  routeEdges = import ./edges/route.nix { inherit lib den; };
  inherit (import ./edge-trace.nix { inherit lib den; })
    extractEdgeTrace
    extractTopLevelEdges
    sortEdges
    ;
  inherit (import ./scope-walk.nix { inherit lib; }) subtreeScopes dedupByKey;
  inherit (import ./edges/materialize.nix { inherit lib den; }) assembleSubtree;
  inherit (import ./edges/pi.nix { inherit lib; }) mkStaticPi;
  inherit (import ./edges/instantiate-edges.nix { inherit lib den; }) mkInstantiateEdges;
  inherit (import ./edges/edge.nix { inherit lib; }) scopeName;
  inherit (import ./edges/provides.nix { inherit lib den; })
    applyProvidesEdges
    dedupProvides
    providesEdges
    ;
  inherit (import ./edges/materialize-unified.nix { inherit lib den; }) materializeUnified;
  instantiateEdges = import ./edges/instantiate.nix { inherit lib; };
  handlers = den.lib.aspects.fx.handlers;

  # Check if `ancestor` is an ancestor of `descendant` in the scopeParent tree.
  isAncestorOf =
    scopeParent: ancestor: descendant:
    let
      parent = scopeParent.${descendant} or null;
    in
    if parent == null || parent == descendant then
      false
    else
      parent == ancestor || isAncestorOf scopeParent ancestor parent;

  # Phase 1: Wrap collected class imports per-scope.
  # Deduplicates modules with identical keys across scopes: when a shared
  # aspect is included by both host and user, it emits class modules in
  # both scopes.  The NixOS module system would eventually dedup by key,
  # but keeping duplicates wastes evaluation and can amplify lib.warn noise.
  wrapPerScope =
    ctx: scopeContexts: scopedClassImportsRaw:
    let
      wrappedPerScope = lib.mapAttrs (
        scopeId: scopeClasses: wrapCollectedClasses (scopeContexts.${scopeId} or ctx) scopeClasses
      ) scopedClassImportsRaw;
      # Per class, concatenate every scope's modules (scope attr-name order)
      # and dedup by key first-occurrence-wins. Equivalent to the old per-class
      # cross-scope seenKeys fold; null-keyed (anon) modules are never deduped.
      scopeData = builtins.attrValues wrappedPerScope;
      allClasses = lib.unique (builtins.concatMap builtins.attrNames scopeData);
      merged = lib.genAttrs allClasses (
        cls: dedupByKey (m: m.key or null) (builtins.concatMap (sd: sd.${cls} or [ ]) scopeData)
      );
    in
    {
      classImports = merged;
      perScope = wrappedPerScope;
    };

  # Phase 2 (policy.provide → target classes) is now an edge constructor:
  # edges/provides.nix applyProvidesEdges. The nest-into-source-bucket
  # materialization + the (policyName/class/path) dedup live there (§B Decision 1).

  # Phase 3: Apply routes. The first positional is the node spawn primitive
  # (threaded with this pipeline's parent scope-tree state) used to resolve a
  # complex-route forward SOURCE with full fleet visibility (replaces the old
  # isolated fxResolve fallback).
  applyRoutes =
    spawnNode: ctx: scopeContexts: rootScopeId: scopeParent: scopeIsolated: scopedRoutes: acc:
    routeEdges.applyRoutes {
      inherit
        scopedRoutes
        scopeContexts
        scopeParent
        scopeIsolated
        rootScopeId
        spawnNode
        ;
      wrappedPerScope = acc.perScope;
      classImports = acc.classImports;
      inherit (handlers) buildForwardAspect;
    };

  # Phase 4: Apply entity instantiation.
  # Resolve the entity scope an instantiate spec targets.
  #
  # register-instantiate records sourceScopeId = currentScope (the parent, e.g.
  # flake-system); the entity's OWN scope is a CHILD created by resolve.to during
  # the same policy fire (push-scope, see modules/policies/flake.nix). push-scope
  # records that child scope keyed by (parentScope, id_hash) in scopeByEntity.
  # Since the resolve.to and the instantiate effect share the same parent scope
  # and carry the same entity record (hence id_hash), the spec looks its scope up
  # DIRECTLY — no name-infix reconstruction. The (parent, id_hash) key handles
  # multi-system same-name entities: id_hash is context-free (kind+name), so two
  # `ben` homes on different systems share an id_hash but have distinct parent
  # (system=…) scopes, keeping their links distinct.
  #
  # T rule (single-child fallback, spec §3d): a spec WITHOUT a recorded entity
  # scope (no id_hash, or no link — e.g. a non-entity collect-perSystem spec)
  # targets its source scope's root. The caller falls through to sourceScopeId.
  entityScopeFor =
    scopeByEntity: spec:
    let
      sid = spec.sourceScopeId or null;
      idHash = spec.id_hash or null;
    in
    if sid != null && idHash != null then scopeByEntity."${sid}\n${idHash}" or null else null;

  # The per-host subtree extraction that produced the complete module set for a
  # host (host-scope + user-scope + route-delivered modules, key-deduped) now
  # routes through the edge materializer's merge mode (edges/materialize.nix
  # assembleSubtree) — the default-fold port. See mkInstantiateArgs.

  # The per-host PROJECTION: from the instantiate-arg bundle + a spec, derive the
  # host subtree's scope universe, isolation-aware contexts, the per-host phase
  # fold (phase3 carries perScope + classImports), and the subtree provides/routes.
  # Factored out so BOTH mkInstantiateArgs (module assembly, unchanged behavior)
  # AND the unifiedEdges edge collector (mkInstantiateEdges projection inputs)
  # consume the SAME projection — they can never diverge on the host subtree.
  # Returns null when the spec has no resolvable host scope (T-rule single-child
  # fallback / non-entity spec).
  perHostProjection =
    {
      augmentedScopeContexts,
      scopedClassImportsRaw,
      scopedProvides,
      scopedRoutes,
      scopeParent,
      scopeByEntity ? { },
      scopeEntityClass ? (_: { }),
      scopeIsolated ? { },
      spawnNodeFn,
      ctx,
    }:
    spec:
    let
      allScopeIds = builtins.attrNames augmentedScopeContexts;
      hostClass = spec.class or "nixos";
      rawHostScopeId = entityScopeFor scopeByEntity spec;
      hostScopeId = if rawHostScopeId != null then rawHostScopeId else spec.sourceScopeId;
    in
    if hostScopeId == null then
      null
    else
      let
        # Isolation-BLIND collect: the per-host re-walk collects
        # sub-phases over the blind set, then extractSubtreeModules extracts
        # over the isolation-AWARE set below. Pass `isolated = {}` explicitly
        # — defaulting it would collapse this deliberate blind/aware split.
        subtreeScopeIds = subtreeScopes {
          inherit scopeParent allScopeIds;
          isolated = { };
          root = hostScopeId;
        };
        subtreeSet = lib.genAttrs subtreeScopeIds (_: true);
        isInSubtree = sid: subtreeSet ? ${sid};
        isAncestor =
          sid:
          let
            parent = scopeParent.${hostScopeId} or null;
          in
          sid == parent || (parent != null && parent != hostScopeId && isAncestorOf scopeParent sid parent);
        isRelevant = sid: isInSubtree sid || isAncestor sid;
        relevantScopeIds = builtins.filter isRelevant allScopeIds;
        scopeEntityClassMap = scopeEntityClass null;
        subtreeContexts = lib.genAttrs subtreeScopeIds (
          sid:
          let
            base = augmentedScopeContexts.${sid};
            entityCls = scopeEntityClassMap.${sid} or null;
          in
          if !(base ? class) && entityCls != null then
            base // { class = entityCls; }
          else if !(base ? class) then
            base // { class = hostClass; }
          else
            base
        );
        subtreeClassImports = lib.genAttrs subtreeScopeIds (sid: scopedClassImportsRaw.${sid} or { });
        subtreeProvides = lib.filterAttrs (sid: _: isRelevant sid) scopedProvides;
        subtreeRoutes = lib.filterAttrs (sid: _: isRelevant sid) scopedRoutes;
        relevantContexts = lib.genAttrs relevantScopeIds (sid: augmentedScopeContexts.${sid});
        subtreePhase1 = wrapPerScope ctx subtreeContexts subtreeClassImports;
      in
      {
        inherit
          hostScopeId
          hostClass
          subtreeScopeIds
          subtreeContexts
          subtreeProvides
          subtreeRoutes
          relevantContexts
          ;
        # The materializeUnified SEED (phase-1 wrap). Both consumers
        # (mkInstantiateArgs module assembly + perHostEdgesFor edge collection)
        # fold it through materializeUnified — module delivery AND the edge
        # collector's content source now flow through the SAME engine, so there is
        # no separate phase2∘phase3 fold to diverge from.
        seed = subtreePhase1;
      };

  # Build instantiateArgs for a spec without calling spec.instantiate.
  # Factored out so both applyInstantiates and hostConfigs can reuse it.
  mkInstantiateArgs =
    argBundle@{
      augmentedScopeContexts,
      scopedClassImportsRaw,
      scopedProvides,
      scopedRoutes,
      scopeParent,
      scopeByEntity ? { },
      scopeEntityClass ? (_: { }),
      scopeEntityKind ? { },
      scopeIsolated ? { },
      spawnNodeFn,
      ctx,
    }:
    spec:
    let
      # perHostProjection takes only the projection inputs; scopeEntityKind is a
      # mkInstantiateArgs-LOCAL concern (Π naming for materializeUnified), so it is
      # stripped from the bundle passed through.
      projBundle = builtins.removeAttrs argBundle [ "scopeEntityKind" ];
      proj = perHostProjection projBundle spec;
      preWalkedModules =
        if proj != null then
          let
            inherit (proj)
              hostScopeId
              hostClass
              subtreeProvides
              subtreeRoutes
              relevantContexts
              seed
              ;
            # Production delivery (Task 17/18): the per-host final extraction folds
            # materializeUnified (doFinalMerge = true → it runs assembleSubtree at
            # hostScopeId), replacing the phase2 (provides) ∘ phase3 (routes) ∘
            # assembleSubtree sequence. The Π's scopeContexts MUST be relevantContexts
            # (NOT subtreeContexts): materializeUnified's complex-forward path reads
            # pi.scopeContexts for source resolution, whereas the old assembleSubtree
            # merge ignored it.
            pi =
              (mkStaticPi {
                rootScopeId = hostScopeId;
                scopeContexts = relevantContexts;
                inherit scopeParent scopeIsolated;
                isolationMode = "aware";
              })
              // {
                inherit scopeEntityKind;
              };
            materialized = materializeUnified {
              inherit pi ctx;
              seed = seed;
              scopedProvides = subtreeProvides;
              scopedRoutes = subtreeRoutes;
              spawnNode = spawnNodeFn;
              inherit (handlers) buildForwardAspect;
            } { doFinalMerge = true; };
            hostModules = materialized.${hostClass} or [ ];
          in
          if hostModules == [ ] then null else hostModules
        else
          null;
      modules =
        if preWalkedModules != null then
          preWalkedModules
        else
          lib.optional (spec ? mainModule) spec.mainModule;
    in
    if spec ? pkgs then
      {
        inherit (spec) pkgs;
        inherit modules;
      }
    else
      {
        inherit modules;
      }
      // lib.optionalAttrs (spec ? system) {
        modules = modules ++ [
          { nixpkgs.hostPlatform = lib.mkDefault spec.system; }
        ];
      };

  # Phase 4: Apply entity instantiation.
  # When hosts were walked in the flake pipeline (via resolve.to "host"),
  # re-run assembly phases per host subtree with the host as rootScopeId.
  # This produces correct routing (identical to per-host fxResolve) while
  # reusing the walk's scope data — including sibling visibility for pipe.collect.
  #
  # Lazy: spec.instantiate is NOT called eagerly. Each output leaf is a thunk
  # that calls spec.instantiate only when accessed (e.g., when someone reads
  # config.flake.nixosConfigurations.cortex). This avoids evaluating all hosts
  # when only one is needed.
  applyInstantiates =
    {
      scopedInstantiates,
      augmentedScopeContexts,
      scopedClassImportsRaw,
      scopedProvides,
      scopedRoutes,
      scopeParent,
      scopeByEntity ? { },
      scopeEntityClass ? (_: { }),
      scopeEntityKind ? { },
      scopeIsolated ? { },
      spawnNodeFn,
      ctx,
    }:
    classImports:
    let
      mkArgs = mkInstantiateArgs {
        inherit
          augmentedScopeContexts
          scopedClassImportsRaw
          scopedProvides
          scopedRoutes
          scopeParent
          scopeByEntity
          scopeEntityClass
          scopeEntityKind
          scopeIsolated
          spawnNodeFn
          ctx
          ;
      };

      allInstantiates = lib.concatLists (lib.attrValues scopedInstantiates);

      # Flake-output T-arm edge construction (spec §2: T = a flake-output path).
      # The descriptors + @system disambiguation are the T-arm-LOCAL rules, shared
      # with the read-only oracle (edge-trace.nix) via edges/instantiate.nix so
      # production and oracle agree on the @system rule (spec §3a). Both touch
      # path + system metadata only — never spec.instantiate (laziness-safe).
      disambiguated = instantiateEdges.disambiguate (instantiateEdges.specDescriptors allInstantiates);

      # Build lazy output tree.  Each leaf calls spec.instantiate on first access.
      instantiateConfigs = map (
        entry: lib.setAttrByPath entry.path (entry.spec.instantiate (mkArgs entry.spec))
      ) disambiguated;
    in
    classImports
    // {
      flake =
        (classImports.flake or [ ])
        ++ lib.optional (instantiateConfigs != [ ]) {
          config = builtins.foldl' lib.recursiveUpdate { } instantiateConfigs;
        };
    };

  # Full resolution: run pipeline, then assemble output through all phases.
  # Shared body — returns both `imports` and the per-scope path set so a single
  # fx.handle backs `resolve` and `resolveWithPaths` (no second pipeline run).
  fxResolveFull =
    mkPipeline:
    {
      class,
      self,
      ctx,
    }:
    let
      result = mkPipeline { inherit class; } { inherit self ctx; };
      scopeContexts = result.state.scopeContexts null;

      scopedClassImportsRaw = result.state.scopedClassImports null;
      scopeParent = result.state.scopeParent null;
      scopedProvides = result.state.scopedProvides null;
      scopedRoutes = result.state.scopedRoutes null;
      # Kind-level isolation marks {scopeId→true}; route collection and subtree
      # extraction skip isolated descendants (the collection root is exempt).
      scopeIsolated = (result.state.scopeIsolated or (_: { })) null;
      # Spec→scope link recorded at scope creation (push-scope), keyed by
      # (parentScope, id_hash). The instantiate spec's scope is resolved through
      # it directly (no name-infix reconstruction); both instantiate call sites
      # (phase4 + the B′ hostConfigs build) use the link.
      scopeByEntity = (result.state.scopeByEntity or (_: { })) null;

      # Scan raw pipe values for config-dependent thunks (functions taking
      # { config, ... }).  If none exist, hostConfigs stays null and
      # assemblePipes skips cross-host instantiation entirely.
      isConfigDependent = val: builtins.isFunction val && (builtins.functionArgs val) ? config;
      hasAnyConfigThunk =
        let
          # Values may be lists of entries, raw functions, or pipe entry
          # records ({ __isPipeEntry; module = <fn>; ... }).
          checkVal =
            v:
            if builtins.isList v then
              builtins.any checkVal v
            else if builtins.isAttrs v && v ? module then
              isConfigDependent v.module
            else
              isConfigDependent v;
        in
        builtins.any (scopeImports: builtins.any checkVal (lib.attrValues scopeImports)) (
          lib.attrValues scopedClassImportsRaw
        );

      # Pipe-data-free host configs for cross-host config-dependent thunk
      # resolution.  Only computed when config-dependent thunks actually exist
      # in the pipe data.  When null, resolveThunks still resolves
      # pipeline-parametric emits, but config-dependent collected emits are
      # deferred (resolveEntry returns them unchanged).
      hostConfigs =
        if !hasAnyConfigThunk then
          null
        else
          let
            allInstantiates = lib.concatLists (lib.attrValues (result.state.scopedInstantiates null));
            specsByHost = builtins.listToAttrs (
              lib.concatMap (
                spec:
                let
                  hasOutput = (spec.intoAttr or [ ]) != [ ];
                  hostScopeId = if hasOutput then entityScopeFor scopeByEntity spec else null;
                in
                if hostScopeId == null then
                  [ ]
                else
                  [
                    {
                      name = hostScopeId;
                      value = spec;
                    }
                  ]
              ) allInstantiates
            );
            mkArgs = mkInstantiateArgs {
              # §A #8/#2/#7 fix (option b): B′ builds peer configs over the
              # hostConfigs-NULL ASSEMBLED contexts (pipe values resolved), not
              # raw scopeContexts. B′'s raw-context use was cycle-forced
              # (assemblePipes-with-hostConfigs needs hostConfigs);
              # but the hostConfigs-NULL pass is cycle-free and resolves every
              # pipeline-parametric pipe value. A pipe-CONSUMING peer aspect (one
              # that reads a quirk value via context, e.g. `{ feat, ... }`) thus
              # gets its pipe value injected — pre-fix the raw context left `feat`
              # unbound and the peer config threw `feat missing` instead of
              # matching its real instantiate output (variant B). Witnessed by
              # deadbugs/bprime-basedrain-crosshost.
              augmentedScopeContexts = augmentedScopeContextsNoCfg;
              # …and over the matching DRAINED import map (deferred includes whose
              # pipeline-parametric pipe-args are now resolved). Pre-fix this was
              # raw scopedClassImportsRaw — the §A #2/#7 baseDrain carry-over.
              scopedClassImportsRaw = drainedForHostConfigs;
              inherit
                scopedProvides
                scopedRoutes
                scopeParent
                scopeByEntity
                ;
              scopeEntityClass = result.state.scopeEntityClass or (_: { });
              inherit scopeIsolated scopeEntityKind;
              spawnNodeFn = spawnNode;
              inherit ctx;
            };
          in
          lib.mapAttrs (_: spec: (spec.instantiate (mkArgs spec)).config) specsByHost;

      # Assemble pipe data into scope contexts before wrapping.
      # Local config thunks are marked for deferred resolution inside evalModules.
      # Cross-host config thunks (from pipe.collect) are resolved using hostConfigs.
      scopeEntityKind = (result.state.scopeEntityKind or (_: { })) null;
      scopeEntityClassMap = (result.state.scopeEntityClass or (_: { })) null;
      augmentedScopeContexts = assemblePipes {
        inherit scopeContexts hostConfigs scopeEntityKind;
        scopeEntityClass = scopeEntityClassMap;
        scopedClassImports = scopedClassImportsRaw;
        scopedPipeEffects = result.state.scopedPipeEffects null;
        inherit scopeParent;
      };

      # §A #8/#2/#7 B′ raw-context ACCIDENT fix (option b: augmented-context build).
      #
      # hostConfigs (re-entry B′) builds each peer host's full config for cross-
      # host config-dependent pipe-thunk resolution. Pre-fix it built those from
      # RAW (undrained) imports, so a peer whose config depends on a DEFERRED
      # include (one that deferred on a pipe-name / enrichment arg) diverged from
      # the peer's real instantiate output (variant B) — throwing `feat missing`
      # instead of resolving. Witnessed by deadbugs/bprime-basedrain-crosshost.
      #
      # The fix: B′ consumes a DRAINED import map. The cycle that forced raw —
      # baseDrain → augmentedScopeContexts → hostConfigs → (B′ would read the
      # drained map) — is broken by draining over a hostConfigs-NULL augmented
      # contexts here. assemblePipes with hostConfigs=null resolves every
      # PIPELINE-PARAMETRIC pipe value (host/user-derived, no config dependency)
      # and leaves config-dependent pipe thunks deferred (__configThunk), so:
      #   - pipe-arg-deferred includes whose pipe is pipeline-parametric (the
      #     common case, incl. the witness `feat`) DRAIN correctly for B′;
      #   - the rarer deferred-include-on-a-CONFIG-dependent-pipe sub-case stays
      #     deferred under B′ (its pipe value genuinely needs a peer's config,
      #     which is the cross-host thunk B′ is mid-resolving — a real recursion
      #     no pass can break; it remains a documented limitation).
      # No cycle: augmentedScopeContextsNoCfg / drainedForHostConfigs / spawnNode /
      # parentState all read RAW scopeContexts + scopedClassImports only, never
      # hostConfigs or augmentedScopeContexts.
      augmentedScopeContextsNoCfg = assemblePipes {
        inherit scopeContexts scopeEntityKind;
        scopeEntityClass = scopeEntityClassMap;
        hostConfigs = null;
        scopedClassImports = scopedClassImportsRaw;
        scopedPipeEffects = result.state.scopedPipeEffects null;
        inherit scopeParent;
      };
      # B′ peer-config drain: only its class-imports map is consumed (the cross-
      # host config build); its spawn edges are NOT collected — B′'s delivery is
      # covered by the per-host mkInstantiateEdges in the unifiedEdges union.
      drainedForHostConfigs = (mkDrained augmentedScopeContextsNoCfg).classImports;

      # Parent-state bundle for node spawns. Uses the RAW scopeContexts and
      # scopedClassImports (not the augmented/drained maps): the spawned node
      # re-derives pipes via its OWN assemblePipes over the merged state, so
      # threading the augmented map would double-apply and feeding the drained
      # map (which depends on this bundle) would cycle. scopeEntityKind is the
      # already-unwrapped binding above. scopedClassImports here covers host +
      # all siblings, which collectAll needs to find fleet peers.
      parentState = {
        inherit
          scopeContexts
          scopeParent
          scopeIsolated
          ctx
          scopeEntityKind
          ;
        scopedClassImports = scopedClassImportsRaw;
        scopedPipeEffects = result.state.scopedPipeEffects null;
        scopedRoutes = result.state.scopedRoutes null;
      };
      # Recursive: a nested complex forward inside a spawned node resolves its
      # source via this SAME threaded primitive (not an isolated pipeline), so
      # nested forwards stay fleet-visible and the resolver contract matches
      # resolveSourceFallback's { from, class, aspect, bindings } call. Nix lets
      # are lazy, so the self-reference is fine — selfRef is only invoked at
      # runtime when a resolved aspect carries a complex non-collected forward,
      # and a finite forward nesting terminates.
      spawnNode = mkSpawnNode {
        inherit wrapPerScope;
        inherit (den.lib.aspects) normalizeRoot;
        inherit (den.lib.aspects.fx.aspect) ctxFromHandlers;
        selfRef = spawnNode;
      } mkPipeline parentState;

      # Post-assembly drain: resolve deferred includes. Parameterized by the
      # augmented contexts the deferred-include resolution reads, so the SAME
      # drain logic produces two maps with different cycle constraints:
      #   - drainedClassImportsRaw       — over the hostConfigs-augmented contexts
      #     (the host's OWN phase1–4 path; hostConfigs already resolved by then).
      #   - drainedForHostConfigs        — over the hostConfigs-NULL augmented
      #     contexts (the cross-host B′ peer-config build, §A #2/#7 ACCIDENT fix).
      # Two categories of deferred includes are drained:
      # 1. Pipe-arg deferred: required args are pipe names, now available
      #    from assemblePipes.
      # 2. Enrichment-deferred: required args (e.g., isNixos) were provided
      #    by a parent scope's policy enrichment but weren't available when
      #    the child scope was walked. The drain inherits parent scope context
      #    to resolve these.
      mkDrained =
        augmentedContexts:
        let
          allDeferred = (result.state.scopedDeferredIncludes or (_: { })) null;
          inherit (den.lib.aspects.fx.keyClassification) classifyKeys;
          inherit (den.lib.aspects.fx.contentUtil) unwrapContentValuesList;
          # Build enriched context for a scope by inheriting parent enrichment.
          # Walks up scopeParent to find enrichment keys not present in the
          # scope's own context.
          # Walk up scopeParent to inherit enrichment from all ancestors.
          enrichedScopeCtx =
            scopeId:
            let
              ownCtx = augmentedContexts.${scopeId} or { };
              inherit' =
                sid:
                let
                  pid = scopeParent.${sid} or null;
                in
                if pid == null || pid == sid then
                  { }
                else
                  let
                    parentCtx = augmentedContexts.${pid} or { };
                    grandparentCtx = inherit' pid;
                  in
                  grandparentCtx // parentCtx;
              ancestorCtx = inherit' scopeId;
              # Only inherit keys not already in the scope's own context.
              inherited = lib.filterAttrs (k: _: !(ownCtx ? ${k})) ancestorCtx;
            in
            ownCtx // inherited;

          baseDrain = lib.foldl' (
            accImports: scopeId:
            let
              deferred = allDeferred.${scopeId} or [ ];
              scopeCtx = enrichedScopeCtx scopeId;
              # Drain all deferred includes whose args are now satisfied,
              # not just pipe-arg deferred ones.
              drainable = builtins.filter (d: builtins.all (k: scopeCtx ? ${k}) (d.requiredArgs or [ ])) deferred;
            in
            if drainable == [ ] then
              accImports
            else
              let
                newEntries = lib.concatMap (
                  d:
                  let
                    child = d.child;
                    classified = classifyKeys null child;
                  in
                  lib.concatMap (
                    k:
                    let
                      modules = unwrapContentValuesList child.${k};
                    in
                    map (module: {
                      __rawEntry = true;
                      class = k;
                      inherit module;
                      ctx = scopeCtx;
                      identity = child.name or "<deferred>";
                      aspectPolicy = child.meta.collisionPolicy or null;
                      globalPolicy = den.config.classModuleCollisionPolicy or "error";
                      isContextDependent = false;
                    }) modules
                  ) classified.classKeys
                ) drainable;
              in
              builtins.foldl' (
                acc: entry:
                acc
                // {
                  ${scopeId} = (acc.${scopeId} or { }) // {
                    ${entry.class} = ((acc.${scopeId} or { }).${entry.class} or [ ]) ++ [ entry ];
                  };
                }
              ) accImports newEntries
          ) scopedClassImportsRaw (builtins.attrNames allDeferred);

          # Materialize deferred node spawn markers (policy.spawn) over the
          # parent scope-tree state, kind-generically. Each marker lives at some
          # spawned-FOR scope (the OWN entity, of kind `ownKind`); the spawned
          # class is re-walked from the projected ASPECT carried on the PARENT
          # scope's own entity record, with the own entity bound under its kind.
          # The walk is threaded with parent + sibling state so fleet-collected
          # pipes resolve to data and collectAll sees every peer. The result is
          # folded into the own scope's class buckets so BOTH phase1 and the
          # phase4 per-host re-walk (over drainedClassImportsRaw) deliver it.
          #
          # The aspect is read from the PARENT scope's own ctx (record under
          # parentKind) — the same record the old code reached via the child
          # scope's ancestor-bound `host`. Default classes fall back to the own
          # record's `classes` (e.g. user type defaults `["homeManager"]`); in
          # practice batteries pass `spec.classes` explicitly so this is unused.
          allHomeNodes = (result.state.scopedSpawns or (_: { })) null;
        in
        # Accumulate BOTH the class-imports map AND the spawn nodes' SURFACED edge
        # sets. Each spawnNode {…} returns { imports; edges; }: `.imports` folds
        # into the class buckets as before; `.edges` is the spawn's real delivered
        # edge set (its default fold + provides + re-applied routes), collected so
        # the host-own invocation can feed unifiedEdges (the oracle's rewalk arm
        # undercounts these). The B′ invocation discards spawnEdges (its delivery
        # is covered by the per-host mkInstantiateEdges, see call sites below).
        lib.foldl'
          (
            acc: scopeId:
            let
              sctx = scopeContexts.${scopeId} or { };
              ownKind = scopeEntityKind.${scopeId} or null;
              ownRecord = if ownKind == null then null else sctx.${ownKind} or null;
              from = scopeParent.${scopeId} or null;
              parentKind = if from == null then null else scopeEntityKind.${from} or null;
              parentRecord =
                if parentKind == null then null else (scopeContexts.${from} or { }).${parentKind} or null;
              specs = allHomeNodes.${scopeId};
              defaultClasses = if ownRecord == null then [ ] else ownRecord.classes or [ ];
              classes = lib.unique (
                lib.concatMap (s: if s.classes != null then s.classes else defaultClasses) specs
              );
            in
            if parentRecord == null || ownRecord == null then
              acc
            else
              let
                # Materialize each class once; capture the FULL spawn return so both
                # `.imports` (class fold) and `.edges` (surfaced set) are available.
                spawned = lib.genAttrs classes (
                  cls:
                  spawnNode {
                    inherit from;
                    class = cls;
                    aspect = parentRecord.aspect;
                    bindings = {
                      ${ownKind} = ownRecord;
                    };
                  }
                );
              in
              {
                classImports = acc.classImports // {
                  ${scopeId} =
                    (acc.classImports.${scopeId} or { })
                    // lib.genAttrs classes (
                      cls: ((acc.classImports.${scopeId} or { }).${cls} or [ ]) ++ spawned.${cls}.imports
                    );
                };
                spawnEdges = acc.spawnEdges ++ lib.concatMap (cls: spawned.${cls}.edges) classes;
              }
          )
          {
            classImports = baseDrain;
            spawnEdges = [ ];
          }
          (builtins.attrNames allHomeNodes);

      # The host's OWN phase1–4 drain, over the hostConfigs-augmented contexts.
      # Surfaces drained.classImports for phases + drained.spawnEdges for unifiedEdges.
      drained = mkDrained augmentedScopeContexts;
      drainedClassImportsRaw = drained.classImports;

      phase1 = wrapPerScope ctx augmentedScopeContexts drainedClassImportsRaw;
      # Production delivery (Task 17): one ordered-dispatch fold over the unified
      # provides+routes edge set, replacing the phase2 (provides) ∘ phase3 (routes)
      # sequence. doFinalMerge = false → returns the raw { classImports; perScope }
      # accumulator (the non-flake output reads the flat classImports, as before).
      pi =
        (mkStaticPi {
          rootScopeId = result.state.rootScopeId;
          scopeContexts = augmentedScopeContexts;
          inherit scopeParent scopeIsolated;
          isolationMode = "aware";
        })
        // {
          inherit scopeEntityKind;
        };
      materialized =
        materializeUnified
          {
            inherit
              pi
              ctx
              scopedProvides
              scopedRoutes
              spawnNode
              ;
            seed = phase1;
            inherit (handlers) buildForwardAspect;
          }
          {
            doFinalMerge = false;
            # Task 18.2: CAPTURE the top-level provides+routes edges the production
            # fold dispatched (materialized.edges), so edgeTrace renders the captured
            # set rather than re-deriving it via extractTopLevelEdges' provides/route
            # arms. The return is acc // { edges; } — classImports reads stay byte-
            # unchanged.
            exposeEdges = true;
          };
      phase4 = applyInstantiates {
        scopedInstantiates = result.state.scopedInstantiates null;
        scopeEntityClass = result.state.scopeEntityClass or (_: { });
        inherit scopeIsolated scopeEntityKind;
        inherit
          augmentedScopeContexts
          scopedProvides
          scopedRoutes
          scopeParent
          scopeByEntity
          ctx
          ;
        # Pass drained class imports so pipe-arg deferred aspects are
        # included in per-host subtree assembly.
        scopedClassImportsRaw = drainedClassImportsRaw;
        spawnNodeFn = spawnNode;
      } materialized.classImports;

      # ===== unifiedEdges component construction =========================
      # The TOP-LEVEL mechanism edge components (default fold + provides + routes +
      # instantiate), built by the SAME constructors the read-only oracle uses, over
      # the SAME end-state — but WITHOUT the oracle's `spawnEdges` rewalk arm (which
      # undercounts each spawn as one edge). The real spawn edges come from
      # drained.spawnEdges (surfaced by the drain-fold), and the per-host / B′
      # instantiate edges come from mkInstantiateEdges below.
      topLevelEdgeParts = extractTopLevelEdges {
        inherit
          scopeContexts
          scopeParent
          scopeIsolated
          scopeEntityKind
          scopedProvides
          scopedRoutes
          ;
        scopedClassImports = scopedClassImportsRaw;
        scopedSpawns = (result.state.scopedSpawns or (_: { })) null;
        scopedInstantiates = (result.state.scopedInstantiates or (_: { })) null;
        rootScopeId = result.state.rootScopeId;
      };

      # The per-host / B′ instantiate edge projections, built from mkInstantiateEdges
      # over the SAME perHostProjection the module assembly uses. `name` normalizes
      # entity scopes to "<kind>:<id_hash>" (matching the oracle/unified set).
      edgeName = scopeName { inherit scopeEntityKind scopeContexts; };
      allInstantiateSpecs = lib.concatLists (lib.attrValues (result.state.scopedInstantiates null));

      # Build the per-host edge set for a spec under the given projection-arg
      # bundle. Returns [] when the spec has no resolvable host scope.
      perHostEdgesFor =
        argBundle: spec:
        let
          proj = perHostProjection argBundle spec;
        in
        if proj == null then
          [ ]
        else
          let
            # The edge collector's content source (the post-provides+routes per-scope
            # presence map) comes from the SAME materializeUnified the module assembly
            # folds — exposeAcc surfaces its accumulator so there is no separate
            # phase2∘phase3 fold (which the old proj.phase3.perScope read).
            pi =
              (mkStaticPi {
                rootScopeId = proj.hostScopeId;
                scopeContexts = proj.relevantContexts;
                inherit scopeParent scopeIsolated;
                isolationMode = "aware";
              })
              // {
                inherit scopeEntityKind;
              };
            materialized =
              materializeUnified
                {
                  inherit pi ctx;
                  seed = proj.seed;
                  scopedProvides = proj.subtreeProvides;
                  scopedRoutes = proj.subtreeRoutes;
                  spawnNode = argBundle.spawnNodeFn;
                  inherit (handlers) buildForwardAspect;
                }
                {
                  doFinalMerge = true;
                  exposeAcc = true;
                  # Task 18.2: CAPTURE the provides+routes edges the per-host fold
                  # dispatched, so mkInstantiateEdges renders the captured set
                  # rather than re-deriving it.
                  exposeEdges = true;
                };
          in
          mkInstantiateEdges {
            name = edgeName;
            inherit scopeParent scopeIsolated;
            inherit (proj)
              hostScopeId
              subtreeScopeIds
              ;
            perScope = materialized.acc.perScope;
            capturedEdges = materialized.edges;
          };

      # Host-own per-host edges: the projection-arg bundle that phase4 uses (the
      # hostConfigs-augmented contexts + drained class imports).
      perHostArgBundle = {
        inherit
          augmentedScopeContexts
          scopeParent
          scopeByEntity
          scopeIsolated
          ctx
          ;
        scopedClassImportsRaw = drainedClassImportsRaw;
        inherit scopedProvides scopedRoutes;
        scopeEntityClass = result.state.scopeEntityClass or (_: { });
        spawnNodeFn = spawnNode;
      };
      perHostEdges = lib.concatMap (perHostEdgesFor perHostArgBundle) allInstantiateSpecs;

      # B′ per-host edges: the cross-host peer-config projection bundle (the
      # hostConfigs-NULL augmented contexts + the matching drained map), mirroring
      # the B′ mkInstantiateArgs bundle. Only meaningful when config-dependent pipe
      # thunks forced the B′ pass; otherwise the projection is over the same scopes
      # the host-own pass covers (the union dedups by sort key, so overlap is inert).
      bprimeArgBundle = {
        augmentedScopeContexts = augmentedScopeContextsNoCfg;
        scopedClassImportsRaw = drainedForHostConfigs;
        inherit
          scopedProvides
          scopedRoutes
          scopeParent
          scopeByEntity
          scopeIsolated
          ctx
          ;
        scopeEntityClass = result.state.scopeEntityClass or (_: { });
        spawnNodeFn = spawnNode;
      };
      bprimeEdges = lib.optionals (hostConfigs != null) (
        lib.concatMap (perHostEdgesFor bprimeArgBundle) allInstantiateSpecs
      );

      # The PRODUCTION delivery-edge object (Task 18.2). The fold-ordered
      # provides+routes portion is the CAPTURE from the production materializeUnified
      # folds (top-level `materialized.edges`, the surfaced spawn `.edges` in
      # drained.spawnEdges, the per-host `.edges` in perHostEdges/bprimeEdges) — NOT
      # a re-derivation, so it is drift-proof. The default-fold (merge) +
      # instantiate (flake-output) edges stay constructor-built: they are the SAME
      # deterministic structural edges production invokes via assembleSubtree /
      # applyInstantiates (no drift surface). This corrects the legacy oracle's
      # spawn rewalk UNDERCOUNT. A lazy thunk — forced only by inspection / the
      # delivery-edges + fx-unified-edges suites, never by normal resolve consumers.
      productionEdgeTrace = sortEdges (
        materialized.edges
        ++ topLevelEdgeParts.defaultFold
        ++ topLevelEdgeParts.instantiateEdgeList
        ++ drained.spawnEdges
        ++ perHostEdges
        ++ bprimeEdges
      );
    in
    {
      imports = phase4.${class} or [ ];
      # Surfaced from the SAME result.state — this is thunked onto state.
      pathSetByScope = result.state.pathSetByScope null;
      # Per-scope ctx + entity-kind, so the entity surface can re-key the path
      # set from scope-string to entity identity (id_hash) for projected
      # hasAspect (see entities/_types.nix:pathSetByScopeOption).
      inherit scopeContexts scopeEntityKind;
      # The production edge object (see productionEdgeTrace above).
      edgeTrace = productionEdgeTrace;
      # One representation: unifiedEdges is an alias for the production edgeTrace.
      unifiedEdges = productionEdgeTrace;
      # The LEGACY end-state re-derivation (edge-trace.nix), WITH its `spawnEdges`
      # rewalk arm (the spawn undercount). Kept as a distinct field so the
      # differential suites can diff the production object against it. Nix attrs
      # are lazy, so this is a thunk — forced only by the differential suites /
      # debug inspection, never by normal resolve consumers.
      legacyEdgeTrace = extractEdgeTrace {
        inherit
          scopeContexts
          scopeParent
          scopeIsolated
          scopeEntityKind
          scopedProvides
          scopedRoutes
          ;
        scopedClassImports = scopedClassImportsRaw;
        scopedSpawns = (result.state.scopedSpawns or (_: { })) null;
        scopedInstantiates = (result.state.scopedInstantiates or (_: { })) null;
        rootScopeId = result.state.rootScopeId;
      };

      # The Task-17 equivalence surface: BOTH the current phase2∘phase3 result AND
      # the materializeUnified result over the SAME live seed (phase1) + the SAME
      # provides/routes/spawn inputs the production phase folds consume. A lazy
      # thunk (like edgeTrace / unifiedEdges) — forced only by the
      # fx-materialize-unified suite, never by normal resolve consumers. This is the
      # byte-equivalence proof for the ordered-dispatch engine: the suite deep-
      # compares `.phaseFold` to `.unified` per topology. Not consumed by production.
      materializeEquiv =
        let
          piTop = pi;
          unifiedInputs = {
            inherit pi;
            seed = phase1;
            inherit
              ctx
              scopedProvides
              scopedRoutes
              spawnNode
              ;
            inherit (handlers) buildForwardAspect;
          };
          # The OLD production path (phase2 provides ∘ phase3 routes), recomputed
          # locally over the SAME live seed. Production now folds materializeUnified
          # directly (above), so this independent recomputation is the equivalence
          # ORACLE the fx-materialize-unified suite deep-compares against `.unified`.
          oraclePhase2 = applyProvidesEdges ctx scopedProvides phase1;
          oraclePhase3 =
            applyRoutes spawnNode ctx augmentedScopeContexts result.state.rootScopeId scopeParent scopeIsolated
              scopedRoutes
              oraclePhase2;
        in
        let
          # The production dispatch order: ALL provides (dedup order) THEN ALL kept
          # routes (orderedKeptRoutes order) — the phase2∘phase3 sequence.
          provideId =
            spec:
            "provide:${spec.__providePolicyName or "<anon>"}/${spec.class}/${
              lib.concatStringsSep "/" (spec.path or [ ])
            }";
          routeId =
            spec:
            "route:${spec.fromClass or "?"}>${spec.intoClass or "?"}@${spec.sourceScopeId or "?"}/${
              lib.concatStringsSep "/" (spec.path or [ ])
            }${lib.optionalString (spec.__complexForward or false) "#complex"}";
          dispatchId = d: if d.kind == "provide" then provideId d.spec else routeId d.spec;
          orderedProvideSpecs = dedupProvides (lib.concatLists (lib.attrValues scopedProvides));
          orderedRouteSpecs = routeEdges.orderedKeptRoutes result.state.rootScopeId (
            lib.concatLists (lib.attrValues scopedRoutes)
          );
          # Production dispatch: all provides (dedup order) then all kept routes.
          phaseFoldDispatch = (map provideId orderedProvideSpecs) ++ (map routeId orderedRouteSpecs);
          # The unified engine's dispatch order via the SAME identity functions.
          unifiedDispatch = map dispatchId (materializeUnified unifiedInputs { exposeDispatch = true; });

          # Task-18 capture: the SAME no-merge call with exposeEdges = true. The
          # accumulator is byte-identical to `unified` (the `// { edges; }` only
          # adds the capture key), and `.edges` carries the folded trace edges the
          # fold dispatched. The suite proves capture fidelity by comparing these
          # to the constructor-built provides+route edges over the same inputs.
          unifiedWithEdges = materializeUnified unifiedInputs {
            doFinalMerge = false;
            exposeEdges = true;
          };
          # The constructor-built oracle: provides trace edges (dedup order) ++
          # route trace edges (kept+ordered), the SAME edges materializeUnified
          # builds internally before its toposort. Same SET as `.edges`, so a
          # sort-key comparison proves capture fidelity.
          piRoot = result.state.rootScopeId;
          edgeName = scopeName {
            scopeEntityKind = pi.scopeEntityKind or { };
            inherit (pi) scopeContexts;
          };
          oracleEdges =
            providesEdges {
              name = edgeName;
              inherit scopedProvides;
            }
            ++ routeEdges.routeEdges {
              name = edgeName;
              inherit (pi) scopeParent;
              rootScopeId = piRoot;
              rawRoutes = routeEdges.orderedKeptRoutes piRoot (lib.concatLists (lib.attrValues scopedRoutes));
            };
        in
        {
          inherit phaseFoldDispatch unifiedDispatch;
          # phase2 ∘ phase3 over the live seed (the production order: all provides
          # then all routes) — recomputed by the local oracle, since production now
          # folds materializeUnified directly.
          phaseFold = oraclePhase3;
          # materializeUnified over the SAME seed, doFinalMerge = false (returns the
          # raw accumulator, byte-comparable to phaseFold). This is the SAME call
          # production uses (`materialized`).
          unified = materializeUnified unifiedInputs { doFinalMerge = false; };
          # Task-18 edge capture surface: the folded edges (with their accumulator)
          # and the constructor-built oracle, for the fx-materialize-unified proof.
          inherit unifiedWithEdges oracleEdges;
          # The doFinalMerge = true variant, comparable to assembleSubtree over the
          # phaseFold result (the final-extraction merge step, unchanged).
          unifiedMerged = materializeUnified unifiedInputs { doFinalMerge = true; };
          phaseFoldMerged = assembleSubtree {
            root = result.state.rootScopeId;
            pi = piTop // {
              perScope = oraclePhase3.perScope;
              classImports = oraclePhase3.classImports;
              provides = scopedProvides;
              routes = scopedRoutes;
            };
          };
        };
    };

  # Back-compatible projection: imports only. Protects deferredModule consumers
  # that assert resolve's output is exactly { imports = …; }.
  fxResolve = mkPipeline: args: { inherit (fxResolveFull mkPipeline args) imports; };

  # imports + per-scope path set, from the SAME fx.handle as fxResolve.
  fxResolveWithPaths = fxResolveFull;

  # Like fxResolve but skips instantiation (phase 4).
  # Returns only class imports from phases 1-3 (wrap, provides, routes).
  # Use for nested resolution where entity instantiation is unwanted
  # (e.g., extracting homeManager modules from a host's aspect tree).
  fxResolveImports =
    mkPipeline:
    {
      class,
      self,
      ctx,
    }:
    let
      result = mkPipeline { inherit class; } { inherit self ctx; };
      scopeContexts = result.state.scopeContexts null;
      scopedClassImportsRaw = result.state.scopedClassImports null;
      scopeParent = result.state.scopeParent null;
      scopeIsolated = (result.state.scopeIsolated or (_: { })) null;

      augmentedScopeContexts = assemblePipes {
        inherit scopeContexts;
        scopeEntityClass = (result.state.scopeEntityClass or (_: { })) null;
        scopedClassImports = scopedClassImportsRaw;
        scopedPipeEffects = result.state.scopedPipeEffects null;
        inherit scopeParent;
      };

      # Analogous parent-state bundle so a nested complex-route forward inside
      # this (non-instantiating) resolution still resolves its source via a
      # threaded spawned node rather than an isolated pipeline. No drain/phase4
      # here, so this only matters for nested node resolution.
      parentState = {
        inherit
          scopeContexts
          scopeParent
          scopeIsolated
          ctx
          ;
        scopeEntityKind = (result.state.scopeEntityKind or (_: { })) null;
        scopedClassImports = scopedClassImportsRaw;
        scopedPipeEffects = result.state.scopedPipeEffects null;
        scopedRoutes = result.state.scopedRoutes null;
      };
      # Recursive: see fxResolve above. selfRef is the threaded primitive itself
      # so a nested complex forward inside a spawned node resolves its source via
      # the same fleet-visible spawn (matching resolveSourceFallback's contract).
      spawnNode = mkSpawnNode {
        inherit wrapPerScope;
        inherit (den.lib.aspects) normalizeRoot;
        inherit (den.lib.aspects.fx.aspect) ctxFromHandlers;
        selfRef = spawnNode;
      } mkPipeline parentState;

      phase1 = wrapPerScope ctx augmentedScopeContexts scopedClassImportsRaw;
      # Production delivery (Task 17): one ordered-dispatch fold over the unified
      # provides+routes edge set, replacing the phase2 (provides) ∘ phase3 (routes)
      # sequence. doFinalMerge = false → returns the raw { classImports; perScope }
      # accumulator; this non-instantiating path reads the flat classImports, as
      # before (no drain / phase4 / assembleSubtree here).
      pi =
        (mkStaticPi {
          rootScopeId = result.state.rootScopeId;
          scopeContexts = augmentedScopeContexts;
          inherit scopeParent scopeIsolated;
          isolationMode = "aware";
        })
        // {
          scopeEntityKind = (result.state.scopeEntityKind or (_: { })) null;
        };
      materialized = materializeUnified {
        inherit pi ctx spawnNode;
        seed = phase1;
        scopedProvides = result.state.scopedProvides null;
        scopedRoutes = result.state.scopedRoutes null;
        inherit (handlers) buildForwardAspect;
      } { doFinalMerge = false; };
    in
    {
      imports = materialized.classImports.${class} or [ ];
    };
in
{
  inherit
    fxResolve
    fxResolveWithPaths
    fxResolveImports
    wrapCollectedClasses
    ;
}
