# Closure-based filters — ancestor closure, neighborhood walks.
{
  lib,
  util,
  graphLib,
  filterByNodes,
  filterUserAspects,
}:
let
  inherit (util)
    neighborhoodByNodes
    ancestorClosureBy
    ;

  # Per-class slice: start from nodes that actively contribute to
  # `className` (perClass.<className>.hasClass == true), then include
  # all ancestors reachable via edges.
  classSlice =
    className: graph:
    ancestorClosureBy (n: n.perClass.${className}.hasClass or false) (filterUserAspects graph);

  # Predicate-based subset view: keep nodes matching `pred` + their
  # direct graph neighbors (one hop in/out). Stage subgraphs are dropped
  # but each node's own `stage` field is preserved.
  neighborhoodOf =
    pred: graph:
    let
      filtered = filterUserAspects graph;
      nbhd = neighborhoodByNodes pred filtered;
    in
    nbhd
    // {
      entityKinds = [ ];
      entityEdges = [ ];
      entityInstances = [ ];
    };

  # Handlers view: nodes with resolution handlers plus immediate neighbors.
  # Graph nodes carry handler info via `style` field (set from trace entry
  # handlers/hasAdapter in graph.nix nodeStyle). This is the correct structural
  # check at the graph IR layer.
  adaptersOnly = graph: neighborhoodOf (n: util.isAdapter n) graph;

  # Parametric aspects view: only aspects that take function arguments
  # (`isParametric = true`). Plus their graph neighbors.
  parametricOnly = graph: neighborhoodOf (n: n.isParametric or false) graph;
in
{
  inherit
    classSlice
    neighborhoodOf
    adaptersOnly
    parametricOnly
    ;
}
