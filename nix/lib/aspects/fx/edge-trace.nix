# edge-trace.nix — the per-component edge-list constructors shared between
# production and the read-only oracle. The live `edgeTrace` (resolve.nix) is the
# CAPTURED production edge object: its fold-ordered provides+routes come straight
# from the production materializeUnified folds. `extractTopLevelEdges` below
# supplies the top-level mechanism lists (default fold, provides, routes, spawns,
# instantiates) both resolve.nix's production object and any end-state oracle
# consume — the retired full-union oracle (`extractEdgeTrace`, the legacy arm of
# the oracle≡production differential) was removed once that proof was complete.
#
# All edge kinds (default folds, simple + complex routes, provides, spawns,
# instantiates) render through the SAME constructors production materializes
# through (edges/default.nix, edges/route.nix, edges/provides.nix,
# edges/instantiate.nix). The ONE residual annotation is `sourceVia = "unresolved"`
# for complex-forward (synthesize) edges: the collected-else-rewalk source choice
# is materialization-time path-dependent, so the trace records identity, not the
# resolved branch (spec §8; see routeEdges). This stays "unresolved" PERMANENTLY —
# it is correct, not a convergence-pending approximation.
#
# Edge record:  { source; target; path; mode; annotations; }
#   S (source)  — collected(scopeName, class) | rewalk(aspect, bindings, class)
#                 | synthesize(forwardId, fromClass, intoClass)
#   T (target)  — { root = scopeName; class; }  (instantiation root)
#                 | { output = attrpath; }      (flake-output)
#   P (path)    — attrpath; [] = merge at root
#   M (mode)    — "merge" | "nest" | "nest-verbatim"
#
# Trace normalization (spec §8): sort key (T, P, S, M); entity scopes named by
# id_hash (parent-blind identity), non-entity scopes by their mkScopeId string;
# rewalk/synthesize edges record the identity triple, NOT resolved content.
{ lib, den, ... }:
let
  # The shared edge record, sort key, scope-naming, and S/T constructors — the
  # ONE edge definition production (edges/default.nix) and this oracle share, so
  # they can never diverge (spec §3a convergence). EXTRACTED to edges/edge.nix.
  inherit (import ./edges/edge.nix { inherit lib; })
    entityKindOf
    scopeName
    mkEdge
    sortEdges
    collected
    rewalk
    synthesize
    rootTarget
    outputTarget
    ;
  # The default-fold edge constructor — the SAME constructor production resolves
  # the per-host extraction through (edges/materialize.nix). v0's inline default-
  # fold arm is REPLACED by this import so extractor and production converge on
  # one constructor (spec §3a).
  inherit (import ./edges/default.nix { inherit lib; }) defaultFoldEdges;
  # The route edge constructor — the SAME constructor production materializes
  # simple + complex routes through (edges/route.nix applyRoutes). v0's inline
  # route arm + its own dedup/suppression re-derivation is REPLACED by this
  # import: the oracle and production now converge on ONE route constructor
  # (spec §3a). The `suppressed` annotations are now EXACT (the constructor's own
  # dedup rules), not the v0 path-dependent approximation; `sourceVia` for complex
  # forwards stays "unresolved" (the collected-else-rewalk source choice is
  # materialization-time path-dependent — see routeEdges' note).
  inherit (import ./edges/route.nix { inherit lib den; }) routeEdges;
  # The provides edge constructor — the SAME constructor production materializes
  # provides through (resolve.nix phase-2 → edges/provides.nix applyProvidesEdges).
  # v0's inline provides arm + its own dedup is REPLACED by this import: oracle and
  # production converge on ONE provides constructor (spec §3a). The two-edge
  # decomposition (nest into source bucket, merge half = default-fold) is recorded
  # by the constructor's `mergeHalf` annotation (§B Decision 1).
  inherit (import ./edges/provides.nix { inherit lib den; }) providesEdges;
  # The flake-output T-arm constructor — the SAME descriptors + @system
  # disambiguation production maps to lazy instantiate thunks (resolve.nix
  # applyInstantiates). The oracle's inline disambiguation re-derivation is
  # REPLACED by this import (spec §3a convergence): the @system rule is now
  # production's, not a parallel render.
  instantiateEdges = import ./edges/instantiate.nix { inherit lib; };
in
rec {
  # extractTopLevelEdges: pipeline end-state → the per-COMPONENT edge lists,
  # UNSORTED. Consumed by resolve.nix's production edge trace, which wants the
  # SAME top-level mechanism lists but drops the `spawnEdges` rewalk arm (it
  # surfaces the real spawn edges from the drain-fold instead) and adds the
  # per-host / B′ instantiate edges. Production consumes the EXACT SAME
  # constructor calls over the SAME end-state as the trace-facing constructors
  # (routeEdges, providesEdges below) it shares with them (spec §3a).
  extractTopLevelEdges =
    {
      scopeContexts,
      scopeParent,
      scopeIsolated,
      scopeEntityKind,
      scopedClassImports,
      scopedRoutes,
      scopedProvides,
      scopedSpawns,
      scopedInstantiates,
      rootScopeId,
    }:
    let
      nameArgs = { inherit scopeEntityKind scopeContexts; };
      name = scopeName nameArgs;
      kindOf = entityKindOf nameArgs;

      allScopeIds = builtins.attrNames scopeContexts;

      # Entity-root scopes: the pipeline root + every isolated scope (an isolated
      # entity is its OWN collection root — isolation = edge-absence into its
      # parent, spec §2). Each is a default-fold T.
      entityRootScopes = lib.unique (
        [ rootScopeId ] ++ builtins.filter (sid: scopeIsolated.${sid} or false) allScopeIds
      );

      # ===== default fold edges ==========================================
      # The SAME constructor production routes the per-host extraction through
      # (edges/default.nix defaultFoldEdges → edges/materialize.nix). v0's inline
      # arm is gone; the oracle and production share one constructor (spec §3a).
      # classContentAt = the per-scope class buckets (only `? class` membership is
      # read for content presence).
      defaultFold = defaultFoldEdges {
        inherit
          name
          scopeParent
          scopeIsolated
          allScopeIds
          entityRootScopes
          ;
        classContentAt = scopedClassImports;
      };

      # ===== provides edges (two-edge decomposition, §B Decision 1) ======
      # Rendered by the SHARED provides constructor (edges/provides.nix
      # providesEdges) — the SAME constructor production materializes provides
      # through (resolve.nix phase-2 → applyProvidesEdges). Each spec → a nest edge
      # into the SOURCE scope's bucket; the merge half is the default-fold edge
      # (annotated mergeHalf). Dedup key = (policyName, class, path), NOT scope-
      # keyed (§B Decision 1).
      providesEdgeList = providesEdges { inherit name scopedProvides; };

      # ===== route edges =================================================
      # Rendered by the SHARED route constructor (edges/route.nix routeEdges) —
      # the SAME constructor production materializes simple routes through
      # (edges/route.nix applyRoutes → materializeRouteEdge). The oracle no longer re-derives
      # suppression: the constructor's own dedup/suppression rules are EXACT here
      # (the `suppressed`/`suppressedByChildKey` annotations are the production
      # decisions, not the v0 approximation). Complex forwards keep
      # `sourceVia = "unresolved"` — see the header: the collected-else-rewalk
      # source is materialization-time path-dependent, so the trace is identity-only.
      rawRoutes = builtins.concatLists (lib.attrValues scopedRoutes);
      routeEdgeList = routeEdges {
        inherit
          name
          scopeParent
          rootScopeId
          rawRoutes
          ;
      };

      # ===== spawn (rewalk) edges ========================================
      # scopedSpawns: each marker lives at an OWN entity scope (ownKind); the
      # spawned class is re-walked from the PARENT scope's own entity aspect,
      # with the own entity bound under its kind → delivered to the own scope
      # root. Identity triple: (parent aspect identity, bound kinds, class).
      # Content is NOT recorded (spec §8 rewalk determinism).
      spawnEdges = builtins.concatLists (
        lib.mapAttrsToList (
          ownSid: specs:
          let
            ownKind = kindOf ownSid;
            from = scopeParent.${ownSid} or null;
            parentKind = if from == null then null else kindOf from;
            parentRec =
              if parentKind == null then null else (scopeContexts.${from} or { }).${parentKind} or null;
            ownRec = if ownKind == null then null else (scopeContexts.${ownSid} or { }).${ownKind} or null;
            # Parent aspect identity: prefer the record's id_hash, else its name.
            aspectId =
              if parentRec == null then "<unknown>" else parentRec.id_hash or parentRec.name or "<unknown>";
            defaultClasses = if ownRec == null then [ ] else ownRec.classes or [ ];
            classes = lib.unique (
              builtins.concatLists (map (s: if s.classes != null then s.classes else defaultClasses) specs)
            );
          in
          map (
            cls:
            mkEdge {
              source = rewalk aspectId [ ownKind ] cls;
              target = rootTarget (name ownSid) cls;
              path = [ ];
              mode = "merge";
              annotations = {
                spawnFrom = if from == null then null else name from;
              };
            }
          ) classes
        ) scopedSpawns
      );

      # ===== instantiate edges (flake-output T-arm) ======================
      # scopedInstantiates → flake-output edges. T = [ "flake" ] ++ intoAttr.
      # Rendered by the SHARED flake-output T-arm constructor (edges/instantiate.nix)
      # — the SAME descriptors + @system disambiguation production maps to lazy
      # instantiate thunks (resolve.nix applyInstantiates). The oracle maps the
      # disambiguated descriptors to edge records instead; both touch path + system
      # metadata only (never spec.instantiate), so this is laziness-safe and the
      # @system rule can never diverge (spec §3a). resolvedRootVia = "scope-link":
      # the entity scope is resolved from the scopeByEntity link recorded at scope
      # creation (push-scope), not reconstructed by a name-infix heuristic.
      allInstantiates = builtins.concatLists (lib.attrValues scopedInstantiates);
      disambiguated = instantiateEdges.disambiguate (instantiateEdges.specDescriptors allInstantiates);
      instantiateEdgeList = map (
        entry:
        let
          spec = entry.spec;
          # @system-qualified when disambiguate rewrote the path-tail (the last
          # element gained an `@<system>` suffix). The constructor owns the rule;
          # the oracle reads its decision off the resulting path.
          baseName = lib.last ([ "flake" ] ++ (spec.intoAttr or [ ]));
          isMultiSystem = lib.last entry.path != baseName;
        in
        mkEdge {
          # Source content comes from the host subtree (collected); the source is
          # the spec's source scope + class.
          source = collected (name (spec.sourceScopeId or rootScopeId)) (spec.class or "nixos");
          target = outputTarget entry.path;
          path = [ ];
          mode = "merge";
          annotations = {
            resolvedRootVia = "scope-link";
            inherit (entry) system;
          }
          // lib.optionalAttrs isMultiSystem {
            disambiguatedTo = lib.concatStringsSep "." entry.path;
          };
        }
      ) disambiguated;

    in
    {
      inherit
        defaultFold
        providesEdgeList
        routeEdgeList
        spawnEdges
        instantiateEdgeList
        ;
    };

  # Re-exported so resolve.nix's production edge trace can sort its union
  # without a second import of edges/edge.nix.
  inherit sortEdges;
}
