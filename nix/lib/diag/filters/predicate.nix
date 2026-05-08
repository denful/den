# Predicate filters — thin wrappers over filterByNodes.
{
  lib,
  util,
  graphLib,
  filterByNodes,
  filterUserAspects,
}:
let
  inherit (util)
    meaningful
    isWrapper
    adjacency
    ;
in
{
  # User-declared view: only nodes that carry `hasClass = true` — i.e.
  # aspects a user explicitly wrote, as opposed to plumbing nodes or
  # module-merge artifacts. Cuts out a lot of pipeline noise without
  # going all the way to `simplified`.
  userDeclaredOnly = graph: filterByNodes (n: n.hasClass or false) (filterUserAspects graph);

  # Pipeline meta view: keep ONLY wrapper/plumbing nodes, dropping all
  # user-facing aspects. Reveals how a single aspect flows through the
  # resolution machinery — `aspect(class) -> self-provide -> cross-provide
  # -> resolve` — at the trace level. Useful for debugging adapter
  # composition.
  pipelineOnly =
    graph: filterByNodes (n: isWrapper n.label) (filterByNodes (n: meaningful n.label) graph);

  # Cross-class view: nodes that contribute to 2+ classes via the
  # perClass attrset (hasClass = true in more than one class). These
  # are the "bridge" aspects spanning nixos + homeManager (or more).
  crossClassOnly =
    graph:
    let
      activeClassCount =
        n:
        builtins.length (
          builtins.filter (c: n.perClass.${c}.hasClass or false) (builtins.attrNames (n.perClass or { }))
        );
    in
    filterByNodes (n: activeClassCount n >= 2) (filterUserAspects graph);

  # Orphans-and-leaves lint view: nodes with no incoming edges that
  # aren't the host itself (orphans) PLUS nodes with no outgoing edges
  # (leaves). Useful for spotting dead code and terminal aspects.
  orphansAndLeaves =
    graph:
    let
      filtered = filterUserAspects graph;
      adj = adjacency filtered.edges;
      isOrphan = n: !(adj.inTo ? ${n.id}) && n.id != filtered.rootId;
      isLeaf = n: !(adj.outOf ? ${n.id});
      pruned = filterByNodes (n: isOrphan n || isLeaf n) filtered;
    in
    pruned
    // {
      entityKinds = [ ];
      entityEdges = [ ];
      entityInstances = [ ];
    };
}
