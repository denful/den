# Structural fold/reshape — cycle-aware expansion, transitive rewrite.
{
  lib,
  util,
  graphLib,
  filterMeaningful,
}:
let
  inherit (util)
    dedupBy
    meaningful
    isWrapper
    adjacency
    ;
in
{
  # Fold wrapper nodes into their children. Wrapper nodes (stage/kind patterns
  # and context nodes) are removed, and their parent edges are rewired to
  # point directly at the wrapper's children.
  foldWrappers =
    graph:
    let
      isContextNode =
        label:
        builtins.elem label [
          "host"
          "default"
          "hm-host"
          "hm-user"
          "user"
        ];
      isFoldable = n: !meaningful n.label || isWrapper n.label || isContextNode n.label;

      foldIds = lib.listToAttrs (
        map (n: {
          name = n.id;
          value = true;
        }) (builtins.filter isFoldable graph.nodes)
      );

      # Adjacency built once; previous implementation linear-scanned
      # graph.edges for every expansion step (O(V*E*depth)).
      adj = adjacency graph.edges;
      childrenOf = id: adj.outOf.${id} or [ ];
      parentsOf = id: adj.inTo.${id} or [ ];

      # Expand edges: replace foldable endpoints with their non-foldable connections.
      # Track visited set to prevent infinite recursion from cycles among foldable nodes.
      expandFrom = expandFromWith { };
      expandFromWith =
        visited: from:
        if !(foldIds ? ${from}) then
          [ from ]
        else if visited ? ${from} then
          [ ]
        else
          lib.concatMap (expandFromWith (visited // { ${from} = true; })) (parentsOf from);
      expandTo = expandToWith { };
      expandToWith =
        visited: to:
        if !(foldIds ? ${to}) then
          [ to ]
        else if visited ? ${to} then
          [ ]
        else
          lib.concatMap (expandToWith (visited // { ${to} = true; })) (childrenOf to);

      expandedEdges = lib.concatMap (
        edge:
        let
          froms = expandFrom edge.from;
          tos = expandTo edge.to;
        in
        lib.concatMap (
          f:
          map (
            t:
            edge
            // {
              from = f;
              to = t;
            }
          ) tos
        ) froms
      ) graph.edges;

      keptNodes = builtins.filter (n: !(foldIds ? ${n.id})) graph.nodes;
      keptIds = lib.listToAttrs (
        map (n: {
          name = n.id;
          value = true;
        }) keptNodes
      );
      keptEdges = dedupBy (e: "${e.from}->${e.to}") (
        builtins.filter (e: keptIds ? ${e.from} && keptIds ? ${e.to} && e.from != e.to) expandedEdges
      );
    in
    graph
    // {
      nodes = keptNodes;
      edges = keptEdges;
    };

  # Fold provider sub-aspects into their parent providers. For a node with
  # providerPath = [ "p" ... ], if a node whose label matches that path exists,
  # the sub-aspect is removed and its edges are rewired to the parent. Chains
  # are resolved transitively so nested sub-aspects collapse all the way up.
  foldProviders =
    graph:
    let
      nodeByLabel = lib.listToAttrs (
        map (n: {
          name = n.fullLabel;
          value = n;
        }) graph.nodes
      );
      parentLabelOf = node: lib.concatStringsSep "/" (node.providerPath or [ ]);
      parentIdOf =
        node:
        let
          pl = parentLabelOf node;
        in
        if pl != "" && nodeByLabel ? ${pl} then nodeByLabel.${pl}.id else null;

      rewritePairs = lib.concatMap (
        n:
        if (n.providerPath or [ ]) != [ ] then
          let
            pid = parentIdOf n;
          in
          if pid != null then
            [
              {
                name = n.id;
                value = pid;
              }
            ]
          else
            [ ]
        else
          [ ]
      ) graph.nodes;
      rewriteMap = lib.listToAttrs rewritePairs;

      # Resolve transitively so chains (a -> b -> c) all fold into c.
      rewireFinal =
        id:
        let
          go =
            cur: visited:
            if !(rewriteMap ? ${cur}) then
              cur
            else if visited ? ${cur} then
              cur
            else
              go rewriteMap.${cur} (visited // { ${cur} = true; });
        in
        go id { };

      keptNodes = builtins.filter (n: !(rewriteMap ? ${n.id})) graph.nodes;
      rewiredEdges = map (
        e:
        e
        // {
          from = rewireFinal e.from;
          to = rewireFinal e.to;
        }
      ) graph.edges;
      keptEdges = dedupBy (e: "${e.from}->${e.to}") (builtins.filter (e: e.from != e.to) rewiredEdges);
    in
    graph
    // {
      nodes = keptNodes;
      edges = keptEdges;
    };

  # Drop entity kind subgraph grouping so nodes render as a single flat DAG.
  flattenEntityKinds =
    graph:
    graph
    // {
      nodes = map (
        n:
        n
        // {
          entityKind = null;
          entityInstance = null;
        }
      ) graph.nodes;
      entityKinds = [ ];
      entityEdges = [ ];
      entityInstances = [ ];
    };

}
