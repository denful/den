# Graph diff — merge two graphs with origin tags.
{
  lib,
  util,
  graphLib,
}:
{
  # Merge two graphs A and B into a single graph where every node and
  # edge carries an `origin` tag: "a" (A only), "b" (B only), "both".
  # Graph a is treated as the base — rootName, rootId, direction are taken from a.
  # Both graphs must share the same node ID namespace for comparison to be meaningful.
  diff =
    { a, b }:
    let
      nodesA = lib.listToAttrs (
        map (n: {
          name = n.fullLabel;
          value = n;
        }) a.nodes
      );
      nodesB = lib.listToAttrs (
        map (n: {
          name = n.fullLabel;
          value = n;
        }) b.nodes
      );
      allKeys = lib.unique (map (n: n.fullLabel) a.nodes ++ map (n: n.fullLabel) b.nodes);
      taggedNodes = map (
        k:
        let
          inA = nodesA ? ${k};
          inB = nodesB ? ${k};
          source = if inA then nodesA.${k} else nodesB.${k};
        in
        source
        // {
          origin =
            if inA && inB then
              "both"
            else if inA then
              "a"
            else
              "b";
        }
      ) allKeys;

      edgesA = lib.listToAttrs (
        map (e: {
          name = "${e.from}->${e.to}";
          value = e;
        }) a.edges
      );
      edgesB = lib.listToAttrs (
        map (e: {
          name = "${e.from}->${e.to}";
          value = e;
        }) b.edges
      );
      allEdgeKeys = lib.unique (lib.attrNames edgesA ++ lib.attrNames edgesB);
      taggedEdges = map (
        k:
        let
          inA = edgesA ? ${k};
          inB = edgesB ? ${k};
          source = if inA then edgesA.${k} else edgesB.${k};
        in
        source
        // {
          origin =
            if inA && inB then
              "both"
            else if inA then
              "a"
            else
              "b";
        }
      ) allEdgeKeys;
    in
    a
    // {
      nodes = taggedNodes;
      edges = taggedEdges;
      entityKinds = a.entityKinds or [ ];
      entityEdges = a.entityEdges or [ ];
      entityInstances = a.entityInstances or [ ];
    };
}
