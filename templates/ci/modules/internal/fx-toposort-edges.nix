# fx-toposort-edges — record-level delivery-edge toposort (Task 16). Hand-built
# edge records exercise the cell model directly: producer→consumer ordering across
# kinds (route producer before its root's final-extraction merge; appendToParent
# producer before the parent merge) and the loud cycle throw on a synthesize 2-cycle.
{ denTest, ... }:
{
  flake.tests.fx-toposort-edges = {

    # A simple route writing (s,"nixos") must precede the final-extraction merge
    # edge whose collectedScopes=["s"] reads (s,"nixos").
    test-route-before-merge = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects.fx.edges) toposort edge;
        # route producer: writes (s,nixos), reads nothing (no collectedScopes).
        route = edge.mkEdge {
          source = edge.collected "s" "nixos";
          target = edge.rootTarget "s" "nixos";
          path = [ "x" ];
          mode = "nest";
        };
        # final-extraction merge: reads (s,nixos) via collectedScopes.
        merge = edge.mkEdge {
          source = edge.collected "s" "nixos";
          target = edge.rootTarget "s" "nixos";
          path = [ ];
          mode = "merge";
          annotations.collectedScopes = [ "s" ];
        };
        ordered = toposort.topoSortEdges [
          merge
          route
        ];
        indexOf =
          pred:
          builtins.head (
            builtins.filter (i: pred (builtins.elemAt ordered i)) (
              builtins.genList (i: i) (builtins.length ordered)
            )
          );
        routeIdx = indexOf (e: e.mode == "nest");
        mergeIdx = indexOf (e: e.mode == "merge");
      in
      {
        expr = routeIdx < mergeIdx;
        expected = true;
      }
    );

    # A 2-cycle: synthesize F1 (a→b) writes (s,b) reads all "a" producers; F2
    # (b→a) writes (s,a) reads all "b" producers. F1 writes a's-reader's-input and
    # vice versa → mutual dependency → loud cycle throw.
    test-synthesize-cycle-throws = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects.fx.edges) toposort edge;
        f1 = edge.mkEdge {
          source = edge.synthesize "F1" "a" "b";
          target = edge.rootTarget "s" "b";
          path = [ ];
          mode = "nest";
        };
        f2 = edge.mkEdge {
          source = edge.synthesize "F2" "b" "a";
          target = edge.rootTarget "s" "a";
          path = [ ];
          mode = "nest";
        };
        result = builtins.tryEval (
          builtins.deepSeq (toposort.topoSortEdges [
            f1
            f2
          ]) "no-throw"
        );
      in
      {
        expr = result.success;
        expected = false;
      }
    );

    # STABLE order: two INDEPENDENT edges (neither reads the other's cell) keep
    # their INPUT order through topoSortEdges. Load-bearing for Task 17 strict-byte
    # (materializeUnified relies on independents preserving the provides-then-routes
    # construction order so the unified fold matches phase2∘phase3 byte-exact).
    test-independent-edges-stable = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects.fx.edges) toposort edge;
        # Two pure producers writing DISTINCT cells, reading nothing — independent.
        a = edge.mkEdge {
          source = edge.collected "s" "nixos";
          target = edge.rootTarget "s" "nixos";
          path = [ "a" ];
          mode = "nest";
        };
        b = edge.mkEdge {
          source = edge.collected "s" "homeManager";
          target = edge.rootTarget "s" "homeManager";
          path = [ "b" ];
          mode = "nest";
        };
        ordered = toposort.topoSortEdges [
          a
          b
        ];
      in
      {
        # Input order [a b] is preserved (a's path stays first).
        expr = map (e: e.path) ordered;
        expected = [
          [ "a" ]
          [ "b" ]
        ];
      }
    );

    # An appendToParent producer (target.root = parent) writes (parent,nixos); the
    # parent's final-extraction merge (collectedScopes=[parent]) reads it → producer
    # precedes parent merge.
    test-append-to-parent-before-merge = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects.fx.edges) toposort edge;
        producer = edge.mkEdge {
          source = edge.collected "child" "nixos";
          target = edge.rootTarget "parent" "nixos";
          path = [ "y" ];
          mode = "nest";
          annotations.appendToParent = true;
        };
        parentMerge = edge.mkEdge {
          source = edge.collected "parent" "nixos";
          target = edge.rootTarget "parent" "nixos";
          path = [ ];
          mode = "merge";
          annotations.collectedScopes = [ "parent" ];
        };
        ordered = toposort.topoSortEdges [
          parentMerge
          producer
        ];
        indexOf =
          pred:
          builtins.head (
            builtins.filter (i: pred (builtins.elemAt ordered i)) (
              builtins.genList (i: i) (builtins.length ordered)
            )
          );
        producerIdx = indexOf (e: e.mode == "nest");
        mergeIdx = indexOf (e: e.mode == "merge");
      in
      {
        expr = producerIdx < mergeIdx;
        expected = true;
      }
    );

  };
}
