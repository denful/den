# Reshape — synthesize alternative graph structures from the base graph.
{
  lib,
  util,
  graphLib,
  filterByNodes,
  filterUserAspects,
}:
let
  inherit (graphLib) emptyNode;
in
{
  # Context hierarchy only: reshape the graph so the entity kinds
  # become the nodes. Aspect content is discarded. The host node is retained
  # and connected to entry kinds (those with no incoming entity edge)
  # so the rendered graph reads "host -> first kind -> ...".
  contextOnly =
    graph:
    let
      kindLabel =
        ek: ek.name + (if ek.ctxKeys != [ ] then " { ${lib.concatStringsSep ", " ek.ctxKeys} }" else "");
      kindNodes = map (
        ek:
        emptyNode
        // {
          id = ek.id;
          label = kindLabel ek;
          fullLabel = kindLabel ek;
          entityKind = "context";
          hasClass = true;
        }
      ) graph.entityKinds;

      kindTargets = map (e: e.to) graph.entityEdges;
      entryKinds = builtins.filter (s: !(builtins.elem s.id kindTargets)) kindNodes;
      hostEdges = map (s: {
        from = graph.rootId;
        to = s.id;
        style = "normal";
        label = null;
      }) entryKinds;
    in
    graph
    // {
      nodes = kindNodes;
      edges = hostEdges ++ graph.entityEdges;
      entityKinds = [ ];
      entityEdges = [ ];
      entityInstances = [ ];
    };

  # Aspect hierarchy only: user aspects with context wrappers folded out
  # and provider-provenance edges dropped. Stage subgraphs are retained as
  # visual grouping (nixos / homeManager / etc).
  aspectsOnly =
    graph:
    let
      filtered = filterUserAspects graph;
    in
    filtered
    // {
      edges = builtins.filter (e: (e.style or "normal") != "provide") filtered.edges;
    };

  # Providers-only view: reshape the graph as a true provider hierarchy.
  #
  # For each node with `providerPath = [a, b, ..., z]` we emit an edge
  # from the immediate-parent-provider node (the one whose fullLabel is
  # `a/b/.../z`) to this node. The result is a proper multi-level tree
  # rooted at top-level provider aspects.
  providersOnly =
    graph:
    let
      filtered = filterUserAspects graph;
      byFull = lib.listToAttrs (
        map (n: {
          name = n.fullLabel;
          value = n;
        }) filtered.nodes
      );
      providerNodes = builtins.filter (n: (n.providerPath or [ ]) != [ ]) filtered.nodes;
      edgeFor =
        n:
        let
          parentFull = lib.concatStringsSep "/" n.providerPath;
          parent = byFull.${parentFull} or null;
        in
        if parent != null then
          [
            {
              from = parent.id;
              to = n.id;
              style = "normal";
              label = null;
            }
          ]
        else
          [ ];
      treeEdges = lib.concatMap edgeFor providerNodes;
      keptIds = lib.listToAttrs (
        map
          (id: {
            name = id;
            value = true;
          })
          (
            lib.unique (
              lib.concatMap (e: [
                e.from
                e.to
              ]) treeEdges
            )
          )
      );
      keptNodes = builtins.filter (n: keptIds ? ${n.id}) filtered.nodes;
    in
    filtered
    // {
      direction = "TD";
      nodes = keptNodes;
      edges = treeEdges;
      entityKinds = [ ];
      entityEdges = [ ];
      entityInstances = [ ];
    };

  # Attribution-based structural-decision view. Groups excluded nodes
  # by their `perClass.<class>.excludedFrom` field. The constraint-owner
  # node is shown alongside its direct inclusion-children (survivors and
  # tombstones side by side).
  decisionsView =
    graph:
    let
      filtered = filterUserAspects graph;
      inclusionEdgesOnly = edges: builtins.filter (e: (e.style or "normal") != "provide") edges;

      inherit (util) adjacency isTombstone;

      # Collect all unique adapter-owner names from perClass metadata.
      ownerNames = lib.unique (
        lib.concatMap (
          n:
          lib.concatMap (
            className:
            let
              pc = n.perClass.${className} or { };
              from = pc.excludedFrom or null;
            in
            if pc.excluded or false && from != null then [ from ] else [ ]
          ) (builtins.attrNames (n.perClass or { }))
        ) filtered.nodes
      );

      # Match owner names to graph node IDs.
      ownerIds = lib.unique (
        lib.concatMap (
          oname: lib.concatMap (n: lib.optional (n.fullLabel == oname) n.id) filtered.nodes
        ) ownerNames
      );

      # Tombstoned nodes attributed to any owner.
      tombstoneIds = map (n: n.id) (builtins.filter isTombstone filtered.nodes);

      # Adjacency from inclusion edges only.
      adj = adjacency (inclusionEdgesOnly filtered.edges);
      childIdsOf = id: adj.outOf.${id} or [ ];
      parentIdsOf = id: adj.inTo.${id} or [ ];

      # For each tombstone, include its inclusion-parent and the
      # parent's other children (surviving siblings) for context.
      tombstoneParentIds = lib.unique (lib.concatMap parentIdsOf tombstoneIds);
      siblingIds = lib.unique (lib.concatMap childIdsOf tombstoneParentIds);

      keepIds = lib.unique (ownerIds ++ tombstoneIds ++ tombstoneParentIds ++ siblingIds);
      keepSet = lib.listToAttrs (
        map (id: {
          name = id;
          value = true;
        }) keepIds
      );
      result = filterByNodes (n: keepSet ? ${n.id}) filtered;
    in
    result
    // {
      entityKinds = [ ];
      entityEdges = [ ];
      entityInstances = [ ];
    };

  # Provider-resolved view: shows each provider aspect alongside its
  # resolved output nodes. Answers "what did each provider produce for
  # this entity?" Provider source nodes link via provide-edges to their
  # resolved children, plus the immediate include-children of each
  # provider sub-aspect show the concrete output.
  providersResolved =
    graph:
    let
      filtered = filterUserAspects graph;
      adj = util.adjacency filtered.edges;

      # Provider nodes: any node with a non-empty providerPath.
      providerIds = map (n: n.id) (builtins.filter (n: (n.providerPath or [ ]) != [ ]) filtered.nodes);

      # For each provider, include its provide-edge targets and its
      # inclusion children (the resolved results).
      childIdsOf = id: adj.outOf.${id} or [ ];
      parentIdsOf = id: adj.inTo.${id} or [ ];

      # Also include the provider source (via provide-edges pointing to it).
      provideEdgeTargets = lib.concatMap (
        e:
        if (e.style or "normal") == "provide" then
          [
            e.from
            e.to
          ]
        else
          [ ]
      ) filtered.edges;

      keepIds = lib.unique (providerIds ++ lib.concatMap childIdsOf providerIds ++ provideEdgeTargets);

      keepSet = lib.listToAttrs (
        map (id: {
          name = id;
          value = true;
        }) keepIds
      );
      result = filterByNodes (n: keepSet ? ${n.id}) filtered;
    in
    result
    // {
      direction = "TD";
    };
}
