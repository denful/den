# Fleet-wide graph IR: composable JSON representation of an entire fleet.
#
# Combines per-host graph IRs into a single IR with:
#   - Host-namespaced node IDs (no collisions across hosts)
#   - Full scope hierarchy (fleet → environment → host → user)
#   - Pipe production/consumption annotations on nodes
#   - Cross-host pipe flow edges
#   - Grouping metadata for interactive expand/collapse
#
# Output shape:
#   {
#     rootName, direction,
#     scopes: [{ id, kind, name, label, parent, children }],
#     nodes: [{ id, label, ..., scope, host, pipes }],
#     edges: [{ from, to, style, label, scope?, crossHost? }],
#     pipes: { <pipeName>: { producers, consumers, flows } },
#   }
{ lib }:
let
  sanitize =
    s:
    lib.replaceStrings
      [
        "/"
        "-"
        " "
        "."
        "@"
        "~"
        ":"
        "("
        ")"
        "{"
        "}"
        ","
        "="
        "'"
        "\""
      ]
      [
        "__"
        "_"
        "_"
        "_"
        "_"
        "_"
        "_"
        "_"
        "_"
        "_"
        "_"
        "_"
        "_"
        "_"
        "_"
      ]
      s;

  hostNameFromScope =
    scopeId:
    let
      parts = lib.splitString "," scopeId;
      match = lib.findFirst (p: lib.hasPrefix "host=" p) null parts;
    in
    if match != null then lib.removePrefix "host=" match else null;

  extractScopeName =
    kind: scopeId:
    let
      parts = lib.splitString "," scopeId;
      match = lib.findFirst (p: lib.hasPrefix "${kind}=" p) null parts;
    in
    if match != null then lib.removePrefix "${kind}=" match else scopeId;

  buildFleetIR =
    {
      fleetCapture,
      hostGraphs, # { "lb-prod" = graphIR; ... }
    }:
    let
      inherit (fleetCapture)
        scopeParent
        scopeEntityKind
        scopeContexts
        scopedPipeEffects
        scopedClassImports
        pipeProducers
        pipeConsumers
        entries
        ctxTrace
        ;

      # --- Scope hierarchy ---

      allScopeIds = builtins.filter (s: s != "__unscoped" && s != "") (builtins.attrNames scopeParent);

      childrenOf =
        parent:
        lib.sort (a: b: a < b) (builtins.filter (s: (scopeParent.${s} or null) == parent) allScopeIds);

      mkScope =
        scopeId:
        let
          kind = scopeEntityKind.${scopeId} or null;
          name = if kind != null then extractScopeName kind scopeId else scopeId;
          children = childrenOf scopeId;
          parent = scopeParent.${scopeId} or null;
          parentNorm = if parent == "__unscoped" || parent == "" then null else parent;
        in
        {
          id = scopeId;
          inherit kind name;
          label = if kind != null then "${kind}: ${name}" else scopeId;
          parent = parentNorm;
          children = children;
          # Context keys available at this scope.
          ctxKeys = builtins.attrNames (scopeContexts.${scopeId} or { });
        };

      scopes = map mkScope allScopeIds;

      # --- Pipe metadata ---

      classKeys = [
        "nixos"
        "homeManager"
        "user"
        "darwin"
      ];
      isPipeKey = k: !builtins.elem k classKeys;

      hostScopes = builtins.filter (s: (scopeEntityKind.${s} or null) == "host") allScopeIds;

      # Pipe producers: from trace data (aspect-level) + class imports.
      producersByPipe = lib.foldl' (
        acc: p: acc // { ${p.pipeName} = (acc.${p.pipeName} or [ ]) ++ [ p ]; }
      ) { } pipeProducers;

      # Pipe consumers: from trace data.
      consumersByPipe = lib.foldl' (
        acc: c: acc // { ${c.pipeName} = (acc.${c.pipeName} or [ ]) ++ [ c ]; }
      ) { } pipeConsumers;

      allPipeNames = lib.unique (
        builtins.attrNames producersByPipe ++ builtins.attrNames consumersByPipe
      );

      # Build flow edges from pipe data.
      # Reuse the pure-consumer heuristic from fleet-views.
      buildPipeFlows =
        pipeName:
        let
          producers = producersByPipe.${pipeName} or [ ];
          consumers = consumersByPipe.${pipeName} or [ ];

          producerHosts = lib.unique (
            builtins.filter (h: h != null) (map (p: hostNameFromScope p.scope) producers)
          );
          consumerHostScopes = lib.unique (
            builtins.filter (h: h != null) (
              map (c: hostNameFromScope c.scope) (builtins.filter (c: c.hasCollect or false) consumers)
            )
          );

          # Pure consumers = collect but don't produce.
          pureConsumerHosts = builtins.filter (h: !builtins.elem h producerHosts) consumerHostScopes;
          effectiveConsumers = if pureConsumerHosts != [ ] then pureConsumerHosts else consumerHostScopes;

          flows = lib.concatMap (
            consumer:
            map (producer: {
              from = producer;
              to = consumer;
              pipe = pipeName;
            }) (builtins.filter (p: p != consumer) producerHosts)
          ) effectiveConsumers;
        in
        {
          producers = map (p: {
            host = hostNameFromScope p.scope;
            aspect = p.aspectIdentity;
            scope = p.scope;
          }) producers;
          consumers = map (c: {
            host = hostNameFromScope c.scope;
            scope = c.scope;
            stages = c.stageTypes or [ ];
            hasCollect = c.hasCollect or false;
          }) (builtins.filter (c: c.hasCollect or false) consumers);
          inherit flows;
        };

      pipes = lib.genAttrs allPipeNames buildPipeFlows;

      # --- Nodes: compose per-host graphs with host-namespaced IDs ---

      prefixId = hostName: id: "${sanitize hostName}__${id}";

      hostNodes =
        hostName: graph:
        let
          pipeProds = builtins.filter (p: hostNameFromScope p.scope == hostName) pipeProducers;
          pipeCons = builtins.filter (
            c: (c.hasCollect or false) && hostNameFromScope c.scope == hostName
          ) pipeConsumers;
        in
        map (
          n:
          let
            # Pipe annotations for this node.
            nodeProduces = lib.unique (
              map (p: p.pipeName) (builtins.filter (p: p.aspectIdentity == (n.fullLabel or n.label)) pipeProds)
            );
            nodeConsumes = lib.unique (
              map (c: c.pipeName) (
                builtins.filter (
                  c:
                  # Consumer is at this host scope and the node is in the same instance.
                  hostNameFromScope c.scope == hostName
                ) pipeCons
              )
            );
          in
          (builtins.removeAttrs n [
            "isExcluded"
            "isReplaced"
          ])
          // {
            id = prefixId hostName n.id;
            # Preserve original ID for cross-referencing.
            originalId = n.id;
            host = hostName;
            scope = n.entityInstance or "host:${hostName}";
            pipes = {
              produces = nodeProduces;
            };
          }
        ) graph.nodes;

      allNodes = lib.concatMap (
        hostName:
        let
          graph = hostGraphs.${hostName} or null;
        in
        if graph != null then hostNodes hostName graph else [ ]
      ) (builtins.attrNames hostGraphs);

      # --- Edges: internal + cross-host ---

      hostEdges =
        hostName: graph:
        map (
          e:
          e
          // {
            from = prefixId hostName e.from;
            to = prefixId hostName e.to;
            host = hostName;
            crossHost = false;
          }
        ) graph.edges;

      allInternalEdges = lib.concatMap (
        hostName:
        let
          graph = hostGraphs.${hostName} or null;
        in
        if graph != null then hostEdges hostName graph else [ ]
      ) (builtins.attrNames hostGraphs);

      # Cross-host pipe flow edges.
      pipeFlowEdges = lib.concatMap (
        pipeName:
        map (flow: {
          from = sanitize "host_${flow.from}";
          to = sanitize "host_${flow.to}";
          style = "pipe";
          label = pipeName;
          pipe = pipeName;
          crossHost = true;
          host = null;
        }) (pipes.${pipeName}).flows
      ) allPipeNames;

      allEdges = allInternalEdges ++ pipeFlowEdges;

      # --- Entity instances with full hierarchy ---

      entityInstances = map (
        scopeId:
        let
          kind = scopeEntityKind.${scopeId} or null;
          name = if kind != null then extractScopeName kind scopeId else scopeId;
          parent = scopeParent.${scopeId} or null;
          parentNorm = if parent == "__unscoped" || parent == "" then null else parent;
        in
        {
          id = sanitize "scope_${scopeId}";
          inherit kind name;
          label = if kind != null then "${kind}: ${name}" else scopeId;
          parent = if parentNorm != null then sanitize "scope_${parentNorm}" else null;
          scopeId = scopeId;
        }
      ) allScopeIds;

    in
    {
      rootName = "fleet";
      direction = "LR";
      inherit
        scopes
        nodes
        pipes
        entityInstances
        ;
      nodes = allNodes;
      edges = allEdges;
    };

  toFleetJSON = args: builtins.toJSON (buildFleetIR args);

in
{
  inherit buildFleetIR toFleetJSON;
}
