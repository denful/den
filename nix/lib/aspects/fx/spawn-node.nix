# Node-spawn primitive.
#
# A spawned node is an independent resolution node spawned from a parent
# (host) scope, threaded with the parent pipeline's resolved scope-tree state
# (host + ALL siblings) so its OWN assemblePipes pass re-derives
# inherited/collected pipe values with full fleet visibility. den-hoag: a
# `spawn` with one read-only inherited edge (neededBy the parent's resolved
# state) — parallel-schedulable, not a sequential route fold.
{ lib, den }:
let
  inherit (import ./assemble-pipes.nix { inherit lib den; }) assemblePipes;
  inherit (import ./scope-walk.nix { inherit lib; }) subtreeScopes;
  inherit (import ./handlers/route.nix { inherit lib; }) routeKey;
  inherit (import ./edges/materialize.nix { inherit lib den; }) assembleSpawnSubtree;
  pipeNamesSet = lib.genAttrs (builtins.attrNames (den.quirks or { })) (_: true);
in
{
  # The phase-1 wrap (wrapPerScope) and the recursive nested-route resolver
  # (selfRef) are injected to avoid a resolve.nix import cycle. mkPipeline +
  # parentState are captured once per run; the inner { from, class, aspect,
  # bindings } call materializes a single class. (provides + routes fold through
  # materializeUnified inside assembleSpawnSubtree, so they are no longer injected.)
  mkSpawnNode =
    {
      wrapPerScope,
      normalizeRoot,
      ctxFromHandlers,
      selfRef,
    }:
    mkPipeline: parentState:
    {
      from,
      class,
      aspect,
      bindings ? { },
      requestingImports ? { },
    }:
    let
      normalized = normalizeRoot aspect;
      seedCtx =
        (parentState.scopeContexts.${from} or parentState.ctx)
        // ctxFromHandlers (aspect.__scopeHandlers or { })
        // bindings;

      # 1. Walk the aspect for the single target class -> the spawned subtree state.
      result = mkPipeline { inherit class; } {
        self = normalized;
        ctx = seedCtx;
      };
      spawnRoot = result.state.rootScopeId;

      # The spawn root must be a distinct child of `from`. A self-parent edge
      # (spawnRoot == from) collapses policyBoundAncestor to null -> zero peers,
      # silently reproducing the single-host bug. Throw with context (not a bare
      # assert) so a future regression names the collapsed scope and its cause.
      _assertRoot =
        if spawnRoot != from then
          null
        else
          throw "den: spawnNode spawn root equals its parent scope '${from}' — a self-parent edge collapses policyBoundAncestor to null and yields zero fleet peers. The seed ctx likely lost its child binding (e.g. `user`).";

      mergedPipeEffects = parentState.scopedPipeEffects // (result.state.scopedPipeEffects null);

      # A pipe `pn` is host-bound when the host scope (`from`) or one of its
      # ancestors ran a pipe policy effect for it (e.g. a fleet `collectAll`).
      ancestorBoundPipe =
        pn:
        let
          go =
            sid:
            if sid == null || sid == spawnRoot then
              false
            else if builtins.any (e: e.pipeName == pn) (mergedPipeEffects.${sid} or [ ]) then
              true
            else
              go (parentState.scopeParent.${sid} or null);
        in
        go from;

      # The node walk re-emits the host aspect's pipe-named keys (e.g.
      # `host-addrs`) at the spawn root. For a HOST-BOUND pipe, that local
      # re-emission makes the spawned scope bind the pipe locally (a self-only
      # value), shadowing inheritance of the host's policy-assembled value
      # (e.g. a fleet collectAll). The spawned scope is a pure consumer there, so
      # strip those keys and let policyBoundAncestor inherit the host's value.
      # Pipes with NO host-bound policy (a plain local emit-and-consume within
      # the host aspect tree) keep their local emission — there is no ancestor
      # value to inherit. Class keys (homeManager, nixos, …) are always kept.
      strippableNames = builtins.filter ancestorBoundPipe (builtins.attrNames pipeNamesSet);
      spawnedClassImports = lib.mapAttrs (
        _: scopeClasses: builtins.removeAttrs scopeClasses strippableNames
      ) (result.state.scopedClassImports null);

      # The requesting (user) scope's OWN quirk emits — the DOWNWARD dual of the
      # `quirkEmits` surfacing at the return below. The projected consumer sits
      # under this spawn root, whose parent chain is `from` (the host), so it never
      # traverses the requesting user scope; its collection of the user's own
      # directly-included quirk emits (e.g. a user aspect's homeManager overlay)
      # would otherwise read []. Merge them into the spawn root's imports for
      # assembly ONLY — never into `spawnedClassImports`, which feeds the upward
      # `quirkEmits` return (folding them there double-counts the emit back at the
      # requesting scope). Host-bound quirks are excluded: they inherit the host's
      # policy-assembled value, matching the strip above.
      requestingQuirkEmits = lib.filterAttrs (
        k: v: (pipeNamesSet ? ${k}) && v != [ ] && !(builtins.elem k strippableNames)
      ) requestingImports;
      spawnRootImports = spawnedClassImports.${spawnRoot} or { };
      spawnRootWithRequesting =
        spawnRootImports // lib.mapAttrs (k: v: (spawnRootImports.${k} or [ ]) ++ v) requestingQuirkEmits;

      # 2. Merge parent state (host + siblings) under the spawned subtree, linking
      #    the spawn root up to `from` so scopeParent walks reach the host's
      #    policy-bound pipes and collectAll scans the fleet siblings.
      mergedScopeContexts = parentState.scopeContexts // (result.state.scopeContexts null);
      mergedClassImports =
        parentState.scopedClassImports
        // spawnedClassImports
        // {
          ${spawnRoot} = spawnRootWithRequesting;
        };
      mergedScopeParent =
        parentState.scopeParent
        // (result.state.scopeParent null)
        // {
          ${spawnRoot} = from;
        };
      mergedScopeIsolated =
        (parentState.scopeIsolated or { }) // ((result.state.scopeIsolated or (_: { })) null);

      # 3. Re-derive pipes over merged state. hostConfigs = null: config-dependent
      #    stay deferred (via __configThunk); pipeline-parametric resolve eagerly.
      augmented = builtins.seq _assertRoot (assemblePipes {
        scopeContexts = mergedScopeContexts;
        scopedClassImports = mergedClassImports;
        scopedPipeEffects = mergedPipeEffects;
        scopeParent = mergedScopeParent;
        scopeEntityKind = parentState.scopeEntityKind;
        hostConfigs = null;
      });

      # The subtree-membership universe: the merged
      # parent DAG keys ∪ the route-scope keys. WIDER than perScope: a route-only
      # scope can sit on the subtree parent-chain without a class bucket. Both the
      # parentSubtreeRoutes filter (below) and the final extraction (inside
      # assembleSpawnSubtree, via Π.allScopeIds) walk over this same universe.
      spawnAllScopeIds = lib.unique (
        builtins.attrNames mergedScopeParent ++ builtins.attrNames parentState.scopedRoutes
      );

      # Isolation-BLIND subtree membership rooted at spawnRoot, over the merged
      # parent DAG. `isolated = {}` is passed EXPLICITLY (documented invariant:
      # isolated entities resolve via resolve.to in the host pipeline,
      # never through spawnNode, so no isolated descendant can appear under
      # spawnRoot). Used ONLY for the parentSubtreeRoutes filter; the final
      # extraction's identical blind walk happens inside assembleSpawnSubtree
      # (Π.isolationMode = "blind"), both over spawnAllScopeIds — one shared walk.
      subtreeSet = lib.genAttrs (subtreeScopes {
        scopeParent = mergedScopeParent;
        isolated = { };
        root = spawnRoot;
        allScopeIds = spawnAllScopeIds;
      }) (_: true);

      # A route that materializes an adapter DECLARES `options.den.fwd.<key>` in
      # the target bucket (handlers/forward.nix mkAdapterAspect, edges/route.nix
      # mkAdapterFunctor). Content definitions merge; an option DECLARATION does
      # not — a second one in the same evalModules is a hard "already declared"
      # error. Of buildForwardAspect's three arms only mkAdapterAspect declares:
      # the top-level adapter arm evaluates inline and mkDirectAspect places
      # content, so both stay.
      #
      # Testing __complexForward FIRST is load-bearing, not stylistic: every
      # complex forward carries an adapterKey (lib/forward.nix always builds
      # one), so a bare `adapterKey != null` would also exclude non-declaring
      # forwards — among them the home-manager battery's own delivery route.
      # The simple-route arm is defensive: adapterKey has one in-tree producer
      # (lib/forward.nix), which only builds complex-forward specs.
      declaresForwardOption =
        r:
        if r.__complexForward or false then
          (r.needsAdapter or false) && !(r.needsTopLevelAdapter or false)
        else
          (r.adapterKey or null) != null;

      # DELIBERATE: parent-pipeline routes sourced inside the spawned
      # subtree MUST re-apply — the spawn re-emits class content at the same scope
      # ids but never re-fires schema policies, so without them a user-schema route
      # (homeLinux->homeManager) never fires and the content drops. This is the
      # `mergedSpawnRoutes` edge-identity dedup: the spawn's OWN route edges win
      # over parent-subtree route edges with the same routeKey identity (an
      # aspect-borne route can register in both pipelines; a duplicated path != []
      # simple route would re-nest content in fresh keyless wrappers and conflict
      # at the target). Order/precedence preserved exactly: freshParent (parent
      # routes whose key ∉ spawn keys) ++ spawnHere.
      #
      # Declaration-bearing parent routes are excluded outright, leaving the
      # parent's copy as the single owner of that declaration: the parent
      # materializes the same route at the same scope and both folds land in one
      # target (the user's home-manager evaluation), so re-applying here emits a
      # second `den.fwd.<key>` declaration.
      #
      # The parent's copy is always present to take over — an excluded route is
      # by construction inside the spawned subtree, and `suppressionVerdicts`'
      # redundant-root rule only fires on a route AT the fold root, which for the
      # parent is an ancestor of spawnRoot.
      #
      # For a forward-only custom class the parent's copy also carries what the
      # spawn would have forwarded, because `getCollectedSource` pulls root-scope
      # content for it. That is NOT general: `filterRootModules` narrows root
      # content to `den.default` modules once fromClass is an entity-owned class,
      # and the parent collects the host bucket unprojected where the spawn would
      # have re-resolved it per user.
      spawnRoutes = result.state.scopedRoutes null;
      parentSubtreeRoutes = lib.filterAttrs (sid: _: subtreeSet ? ${sid}) parentState.scopedRoutes;
      mergedSpawnRoutes =
        spawnRoutes
        // lib.mapAttrs (
          sid: parentRoutes:
          let
            spawnHere = spawnRoutes.${sid} or [ ];
            spawnKeys = lib.genAttrs (map (routeKey sid) spawnHere) (_: true);
            freshParent = builtins.filter (
              r: !(spawnKeys ? ${routeKey sid r}) && !(declaresForwardOption r)
            ) parentRoutes;
          in
          freshParent ++ spawnHere
        ) parentSubtreeRoutes;

      # The spawn's provides + routes fold + isolation-BLIND, dedup-FREE final
      # extraction, expressed over the edge machinery (materializeUnified inside
      # assembleSpawnSubtree). wrapPerScope is forwarded (injection seam preserved —
      # no resolve.nix import cycle); the inline phase1/phase2/phase3 + subtree
      # concat dissolved into one entry. The fold aggregates across ALL merged
      # scopes (host + sibling users), so the extraction is subtree-restricted via
      # Π.allScopeIds + isolationMode="blind" to avoid leaking a peer user's
      # content; fleet pipe values still resolve correctly because assemblePipes ran
      # over the full merged state before the fold.
    in
    # The self-parent assert is forced via `augmented` (which the fold reads),
    # matching the prior inline form's laziness: the throw surfaces only when this
    # node's content is actually collected, not at attrset construction.
    assembleSpawnSubtree {
      inherit
        class
        spawnRoot
        mergedScopeParent
        mergedScopeIsolated
        mergedSpawnRoutes
        selfRef
        wrapPerScope
        ;
      ctx = parentState.ctx;
      inherit augmented;
      inherit mergedClassImports;
      # Merged parent + spawned entity kinds — the surfaced edges' scopeName map.
      scopeEntityKind = parentState.scopeEntityKind // ((result.state.scopeEntityKind or (_: { })) null);
      ownProvides = result.state.scopedProvides null;
      allScopeIds = spawnAllScopeIds;
    }
    // {
      # The aspect is processed in BOTH the requesting (user) scope and this
      # spawned home node, so its quirks must materialize in both. Surface the
      # NON-host-bound ones (host-bound quirks were stripped above and inherited
      # from the host instead) across ALL scopes in the spawned subtree, so the
      # caller (resolve.nix) can also fold them into the requesting scope's quirk
      # buckets — letting a user-scope broadcast/collect/expose of a
      # host-aspects-projected quirk behave as if the user included the aspect.
      quirkEmits =
        let
          allEmits = lib.mapAttrsToList (
            sid: scopeClasses: lib.filterAttrs (k: v: (pipeNamesSet ? ${k}) && v != [ ]) scopeClasses
          ) spawnedClassImports;
        in
        lib.zipAttrsWith (name: values: lib.concatLists values) allEmits;
    };
}
