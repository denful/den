# toposort.nix — the GENERAL record-level delivery-edge toposort (Task 16).
# Generalizes route.nix's per-route `topoSort` (which keyed deps only on
# sourceScopeId, the known blind spot) to a cell-model toposort over the UNIFIED
# edge set: cross-kind (provides/route/synthesize/default-fold/instantiate),
# cross-field, cross-root. A producer that WRITES a (scope,class) cell must fire
# before any edge that READS that cell.
#
# CELL MODEL (B15 proof). Producers WRITE; only the final-extraction merge,
# synthesize, and instantiate edges READ produced cells. Provides + simple routes
# read FROZEN phase-1 inputs, so they depend on NOTHING.
#
#   writeCell(edge):
#     target {root;class}  → cell (target.root, target.class). Covers EVERY
#                            producer: provides nest, route nest/merge,
#                            appendToParent (constructor already set
#                            target.root=parent), synthesize. No special-case.
#     target {output}      → writes nothing readable (terminal instantiate).
#
#   readCells(edge):
#     merge + annotations.collectedScopes  → { (sid, target.class) : sid ∈
#                            collectedScopes } — the per-root final extraction
#                            reads every subtree-scope bucket at its class.
#     synthesize source     → (target.root, fromClass) ∪ (rootName, fromClass) ∪
#                            the FLAT aggregate of fromClass: i.e. EVERY producer
#                            of fromClass at ANY scope (route.nix:568 reads the
#                            flat acc.classImports.${fromClass}). Modeled as
#                            "depends on all writers of fromClass".
#     collected source + target {output} (instantiate) → (source.collected.scope,
#                            source.collected.class) — the host subtree bucket;
#                            depends on that host's final-extraction merge.
#     anything else (provides / simple route — collected source, no
#                            collectedScopes, root target) → {} (frozen phase-1
#                            inputs, B15). The presence of collectedScopes is what
#                            distinguishes a READING merge from a producing one.
#
# Ambiguity rule: any edge shape not matched above defaults to readCells = {} —
# a pure producer. Conservative: never invents a false cycle.
#
# The DAG is built over INDICES (edge records carry functions and are not
# comparable / hashable); the cell match is a pure record inspection (no content
# eval). Kahn toposort with a loud cycle throw mirroring route.nix's message.
{ lib }:
let
  cellKey = scope: class: scope + "/" + class;

  # The (scope,class) cell this edge WRITES, or null for a terminal instantiate.
  writeCellOf =
    e:
    let
      t = e.target;
    in
    if t ? output then null else cellKey t.root t.class;

  # The cell keys this edge READS (see the CELL MODEL header). The rootName for a
  # synthesize edge's extra root-slice read is the root scope NAME; the unified set
  # uses normalized scope names throughout, but the synthesize FLAT read already
  # subsumes "all producers of fromClass at ANY scope", so the root-slice and
  # own-scope cells are members of that flat set. We therefore model the synthesize
  # read as the flat fromClass set (computed against all write cells by class).
  #
  # For non-synthesize edges the read is the bounded cell set the model specifies.
  readCellsOf =
    writeClassScopes: e:
    let
      s = e.source;
      t = e.target;
      ann = e.annotations or { };
    in
    # Final-extraction merge: reads every collected subtree scope at its class.
    if e.mode == "merge" && ann ? collectedScopes then
      map (sid: cellKey sid t.class) ann.collectedScopes
    # Synthesize (complex forward): reads the FLAT aggregate of fromClass — every
    # producer of fromClass at ANY scope.
    else if s ? synthesize then
      map (scope: cellKey scope s.synthesize.fromClass) (
        writeClassScopes.${s.synthesize.fromClass} or [ ]
      )
    # Instantiate: collected source feeding a flake-output target reads the host's
    # subtree bucket cell.
    else if s ? collected && (t ? output) then
      [ (cellKey s.collected.scope s.collected.class) ]
    # Provides / simple routes / anything else: frozen phase-1 inputs (B15) — and
    # the conservative default for unmatched shapes.
    else
      [ ];

  # A short edge label for the cycle-throw chain: target cell + source kind.
  labelOf =
    e:
    let
      t = e.target;
      s = e.source;
      srcKind =
        if s ? synthesize then
          "synthesize:${s.synthesize.fromClass}>${s.synthesize.intoClass}"
        else if s ? collected then
          "collected:${s.collected.scope}/${s.collected.class}"
        else if s ? rewalk then
          "rewalk:${s.rewalk.aspect}"
        else
          "?";
    in
    if t ? output then
      "out:${lib.concatStringsSep "." t.output}<-${srcKind}"
    else
      "${t.root}/${t.class}[${e.mode}]<-${srcKind}";

  topoSortEdges =
    edges:
    let
      n = builtins.length edges;
      edgeAt = i: builtins.elemAt edges i;
      idxs = lib.range 0 (n - 1);

      # cell → [ indices of edges that WRITE it ]. The producer map.
      writers = builtins.foldl' (
        acc: i:
        let
          c = writeCellOf (edgeAt i);
        in
        if c == null then acc else acc // { ${c} = (acc.${c} or [ ]) ++ [ i ]; }
      ) { } idxs;

      # class → [ distinct scope names with a write cell at that class ]. The flat
      # read universe for synthesize edges (every producer of fromClass anywhere).
      writeClassScopes = builtins.foldl' (
        acc: i:
        let
          t = (edgeAt i).target;
        in
        if t ? output then
          acc
        else
          acc // { ${t.class} = lib.unique ((acc.${t.class} or [ ]) ++ [ t.root ]); }
      ) { } idxs;

      # Dependency indices of edge i: every writer of any cell i reads, plus any
      # index the caller pinned via `__afterEdges` (a read the cell model cannot
      # see from the record alone), minus self.
      depsOf =
        i:
        let
          e = edgeAt i;
          cells = readCellsOf writeClassScopes e;
          writerIdxs = lib.unique (
            builtins.concatLists (map (c: writers.${c} or [ ]) cells) ++ (e.__afterEdges or [ ])
          );
        in
        builtins.filter (j: j != i) writerIdxs;

      # Kahn toposort over the index DAG. On a remaining cycle, throw with the
      # participating edge chain (mirrors route.nix:496 — a detected cycle is a
      # loud config error).
      #
      # STABLE: `ready` is emitted in ascending index order (it filters
      # `remaining`, which starts as `idxs` ascending and is only ever shrunk by a
      # membership filter that preserves order), so independent edges preserve
      # input/construction order — load-bearing for Task 17 strict-byte
      # (materializeUnified relies on the unified provides-then-routes edge list
      # keeping provides BEFORE routes among independents, matching phase2∘phase3).
      go =
        emitted: remaining:
        if remaining == [ ] then
          [ ]
        else
          let
            es = lib.genAttrs (map toString emitted) (_: true);
            ready = builtins.filter (i: builtins.all (j: es ? ${toString j}) (depsOf i)) remaining;
          in
          if ready == [ ] then
            throw "den materialize: delivery-edge cycle among [ ${
              lib.concatStringsSep " -> " (map (i: labelOf (edgeAt i)) remaining)
            } ] — a delivery edge's source depends on its own output transitively."
          else
            let
              readySet = lib.genAttrs (map toString ready) (_: true);
            in
            ready ++ go (emitted ++ ready) (builtins.filter (i: !(readySet ? ${toString i})) remaining);
    in
    map edgeAt (go [ ] idxs);
in
{
  inherit topoSortEdges;
}
