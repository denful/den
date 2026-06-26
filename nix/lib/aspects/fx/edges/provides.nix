# provides.nix — the provides edge constructor (spec §2 corollary 4, §B
# Decision 1). A `policy.provide` spec materializes as a TWO-EDGE composition
# `nest ∘ merge`:
#
#   1. a NEST edge `(S = the provided module, T = (sourceScope-bucket, class),
#      P = spec.path, M = nest)` — the `setAttrByPath path module` construction;
#   2. the DEFAULT MERGE edge every entity-root scope already has (corollary 1) —
#      the nested module is appended into the SOURCE scope's own bucket
#      (perScope.${sid}.${class}), and the default subtree fold carries it to the
#      entity root exactly like any other collected content.
#
# This file emits ONLY the nest edge into the source scope's bucket; the merge
# half rides the existing default-fold edge (do NOT emit a literal second edge in
# materialization — the trace keeps the `mergeHalf = "default-fold"` annotation
# per the §3a oracle convention). M stays the closed enum — provides adds no mode.
#
# Edge identity / dedup is the composite key `(policyName, intoClass, path)` — NOT
# scope-keyed: two provides from one policy into one class+path collapse to one
# edge regardless of which scope registered them (first-occurrence-wins). This is
# deliberately coarser than route dedup (which keys on scope): provides identity
# is policy-authored intent, not scope of registration (§B Decision 1).
#
# Two projections share ONE dedup (dedupProvides):
#   - the trace-facing edge RECORD (identity + annotations, no content) consumed
#     by the read-only oracle (edge-trace.nix);
#   - the MATERIALIZATION (the actual wrapped module appended to the source-scope
#     bucket) consumed by resolve.nix's phase-2 fold, replacing applyProvides.
{ lib, den }:
let
  inherit (import ./edge.nix { inherit lib; }) mkEdge collected rootTarget;
  inherit (import ../scope-walk.nix { inherit lib; }) dedupByKey;

  # Dedup provides by composite key (policyName/class/path). Null-keyed specs
  # (no __providePolicyName) are always kept. First-occurrence wins.
  dedupProvides = dedupByKey (
    s:
    let
      pn = s.__providePolicyName or null;
    in
    if pn != null then "${pn}/${s.class}/${lib.concatStringsSep "/" (s.path or [ ])}" else null
  );

  # ===== materialization (ported from resolve.nix:applyProvides) ==========
  # Apply the deduped provides specs onto an accumulator { classImports; perScope; }.
  # Each spec → the nest-at-P module (setAttrByPath), wrapped via wrapClassModule
  # (module-identity wrapping, NOT a mode); unsatisfied wraps are DROPPED. The
  # wrapped module is appended to BOTH the flat classImports aggregate AND the
  # SOURCE scope's perScope bucket — the latter is the merge half (subtree-
  # collectible, visible to a later route's getCollectedSource / subtree walk).
  #
  #   ctx           — the pipeline base ctx (the wrap context for every provide).
  #   scopedProvides — sid → [ provide specs ] (the registered provides).
  #   acc           — { classImports; perScope; } (phase-1 output).
  # Materialize ONE provides spec onto the accumulator. Factored out of the
  # applyProvidesEdges fold (additive) so a single provides spec can be
  # materialized in interleaved order by materializeUnified (Task 17) — the per-
  # spec body is IDENTICAL, so applyProvidesEdges (= foldl' applyOneProvide) and
  # the interleaved fold land byte-identical content.
  applyOneProvide =
    ctx: prev: spec:
    let
      targetClass = spec.class;
      path = spec.path or [ ];
      sid = spec.sourceScopeId;
      # Nest-at-P construction (P=[] degenerates to a plain merge contribution).
      rawModule = if path == [ ] then spec.module else lib.setAttrByPath path spec.module;
      wrapped = den.lib.aspects.fx.aspect.wrapClassModule {
        inherit ctx;
        class = targetClass;
        module = rawModule;
        aspectPolicy = null;
        globalPolicy = null;
      };
      wrappedMod =
        if wrapped.unsatisfied or false then
          [ ]
        else
          let
            loc = "${targetClass}@<provide>/${lib.concatStringsSep "/" path}";
          in
          [ (lib.setDefaultModuleLocation loc wrapped.module) ];
    in
    {
      classImports = prev.classImports // {
        ${targetClass} = (prev.classImports.${targetClass} or [ ]) ++ wrappedMod;
      };
      perScope = prev.perScope // {
        ${sid} = (prev.perScope.${sid} or { }) // {
          ${targetClass} = ((prev.perScope.${sid} or { }).${targetClass} or [ ]) ++ wrappedMod;
        };
      };
    };

  applyProvidesEdges =
    ctx: scopedProvides: acc:
    let
      allProvides = dedupProvides (lib.concatLists (lib.attrValues scopedProvides));
    in
    builtins.foldl' (applyOneProvide ctx) acc allProvides;

  # ===== trace-facing provides edge constructor (§8 identity, no content) =
  # Renders the deduped provides specs as edge RECORDS for the oracle. Each is the
  # NEST edge into the source scope's bucket (the merge half is the default-fold
  # edge, annotated). P=[] degenerates to a merge contribution (no nesting).
  #
  #   name  — sid → stable scope name (edge.nix scopeName).
  #   scopedProvides — sid → [ provide specs ].
  providesEdges =
    { name, scopedProvides }:
    let
      allProvides = builtins.concatLists (lib.attrValues scopedProvides);
      dedupedProvides = dedupProvides allProvides;
    in
    map (
      spec:
      let
        path = spec.path or [ ];
        sid = spec.sourceScopeId;
      in
      mkEdge {
        source = collected (name sid) spec.class;
        target = rootTarget (name sid) spec.class;
        inherit path;
        mode = if path == [ ] then "merge" else "nest";
        annotations = {
          providesPolicyName = spec.__providePolicyName or null;
          # The merge half (delivery to the entity root) is the default-fold edge;
          # this nest edge only constructs the placed module (§B Decision 1).
          mergeHalf = "default-fold";
        };
      }
    ) dedupedProvides;
in
{
  inherit
    dedupProvides
    applyOneProvide
    applyProvidesEdges
    providesEdges
    ;
}
