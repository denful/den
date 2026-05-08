# JSON renderer for the diagram graph IR.
#
# Serialises a graph value to a JSON string suitable for tooling
# consumption (e.g. the fx-diagram integration).
#
# Node fields are derived from `graphLib.emptyNode` so the exported
# schema stays in sync with graph.nix automatically.  The structural-
# only booleans `isExcluded` and `isReplaced` are stripped because they
# are filter-internal state, not meaningful to downstream consumers.
{
  lib,
  graphLib,
}:
let
  # Fields present in emptyNode that are internal to the filter pipeline
  # and should not appear in the serialised output.
  internalNodeFields = [
    "isExcluded"
    "isReplaced"
  ];

  sanitizeNode =
    n:
    lib.removeAttrs (lib.intersectAttrs graphLib.emptyNode n) internalNodeFields
    // lib.optionalAttrs (n ? origin) { inherit (n) origin; };

  sanitizeEdge =
    e:
    {
      inherit (e)
        from
        to
        style
        label
        ;
    }
    // lib.optionalAttrs (e ? origin) { inherit (e) origin; };

in
{
  toJSON =
    g:
    builtins.toJSON {
      rootName = g.rootName or "";
      rootId = g.rootId or "";
      direction = g.direction or "LR";
      nodes = map sanitizeNode (g.nodes or [ ]);
      edges = map sanitizeEdge (g.edges or [ ]);
      entityKinds = g.entityKinds or [ ];
      entityEdges = g.entityEdges or [ ];
      entityInstances = g.entityInstances or [ ];
    };
}
