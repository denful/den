# Barrel — import all filter sub-modules and merge exports.
{
  lib,
  util,
  graphLib,
}:
let
  inherit (util) filterByNodes meaningful;

  # Core composite used by many sub-modules.
  filterMeaningful = filterByNodes (n: meaningful n.label);

  foldMod = import ./fold.nix {
    inherit
      lib
      util
      graphLib
      filterMeaningful
      ;
  };

  filterUserAspects = graph: foldMod.foldWrappers (filterMeaningful graph);

  shared = {
    inherit
      lib
      util
      graphLib
      filterByNodes
      filterUserAspects
      ;
  };

  predicate = import ./predicate.nix shared;
  closure = import ./closure.nix shared;
  reshape = import ./reshape.nix shared;
  presence = import ./presence.nix shared;
  diffMod = import ./diff.nix { inherit lib util graphLib; };

  # `simplified` composes across fold + reshape.
  simplified = graph: foldMod.foldProviders (foldMod.flattenEntityKinds (reshape.aspectsOnly graph));

  # Fan-in / fan-out metrics.
  fanMetrics =
    graph:
    let
      filtered = filterUserAspects graph;
      inCounts = lib.foldl' (acc: e: acc // { ${e.to} = (acc.${e.to} or 0) + 1; }) { } filtered.edges;
      outCounts = lib.foldl' (
        acc: e: acc // { ${e.from} = (acc.${e.from} or 0) + 1; }
      ) { } filtered.edges;
    in
    lib.sort (a: b: a.total > b.total) (
      map (
        n:
        let
          fanIn = inCounts.${n.id} or 0;
          fanOut = outCounts.${n.id} or 0;
        in
        {
          inherit (n)
            id
            label
            fullLabel
            entityKind
            class
            ;
          inherit fanIn fanOut;
          total = fanIn + fanOut;
        }
      ) filtered.nodes
    );
in
predicate
// foldMod
// closure
// reshape
// presence
// diffMod
// {
  inherit
    filterMeaningful
    filterUserAspects
    simplified
    fanMetrics
    ;
}
