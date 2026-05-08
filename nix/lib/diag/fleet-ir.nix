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

      # Build pipe metadata and flow edges, scoped by parent (siblings only).
      # pipe.collect only reaches siblings (same scopeParent).
      hostParentScopes = lib.unique (map (hScope: scopeParent.${hScope} or null) hostScopes);

      buildPipeData =
        pipeName:
        let
          producers = producersByPipe.${pipeName} or [ ];
          consumers = consumersByPipe.${pipeName} or [ ];

          flowsPerParent = lib.concatMap (
            parentScope:
            let
              siblingHosts = builtins.filter (h: (scopeParent.${h} or null) == parentScope) hostScopes;
              siblingNames = builtins.filter (h: h != null) (map hostNameFromScope siblingHosts);
              localProducerNames = lib.unique (
                builtins.filter (h: h != null) (
                  map (p: hostNameFromScope p.scope) (
                    builtins.filter (p: builtins.elem (hostNameFromScope p.scope) siblingNames) producers
                  )
                )
              );
              localConsumerNames = lib.unique (
                builtins.filter (h: h != null) (
                  map (c: hostNameFromScope c.scope) (
                    builtins.filter (
                      c: (c.hasCollect or false) && builtins.elem (hostNameFromScope c.scope) siblingNames
                    ) consumers
                  )
                )
              );
              pureConsumers = builtins.filter (h: !builtins.elem h localProducerNames) localConsumerNames;
              effectiveConsumers = if pureConsumers != [ ] then pureConsumers else localConsumerNames;
            in
            lib.concatMap (
              consumer:
              map (producer: {
                from = producer;
                to = consumer;
                inherit pipeName;
              }) (builtins.filter (p: p != consumer) localProducerNames)
            ) effectiveConsumers
          ) hostParentScopes;
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
          flows = flowsPerParent;
        };

      pipes = lib.genAttrs allPipeNames buildPipeData;

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

      allAspectNodes = lib.concatMap (
        hostName:
        let
          graph = hostGraphs.${hostName} or null;
        in
        if graph != null then hostNodes hostName graph else [ ]
      ) (builtins.attrNames hostGraphs);

      # --- Scope hierarchy nodes ---
      # Create nodes for fleet, environment, host, user, flake-system scopes
      # so the full resolution tree is visible in the graph.

      scopeNodeId = scopeId: sanitize "scope_${scopeId}";

      scopeShape =
        kind:
        if kind == "fleet" then
          "rect"
        else if kind == "environment" then
          "hexagon"
        else if kind == "host" then
          "rect"
        else if kind == "user" then
          "rect"
        else
          "rect";

      scopeNodes = map (
        scopeId:
        let
          kind = scopeEntityKind.${scopeId} or null;
          name = if kind != null then extractScopeName kind scopeId else scopeId;
        in
        {
          id = scopeNodeId scopeId;
          label = if kind != null then "${kind}: ${name}" else scopeId;
          fullLabel = if kind != null then "${kind}: ${name}" else scopeId;
          pathKey = scopeId;
          shape = scopeShape kind;
          style = "default";
          entityKind = kind;
          entityInstance = if kind != null then "${kind}:${name}" else null;
          classes = [ ];
          class = "";
          perClass = { };
          fnArgNames = [ ];
          isParametric = false;
          isProvider = false;
          providerPath = [ ];
          hasClass = false;
          isPolicyDispatch = false;
          policyName = null;
          from = null;
          to = null;
          host = null;
          scope = scopeId;
          originalId = scopeId;
          isScope = true;
          pipes = {
            produces = [ ];
          };
        }
      ) allScopeIds;

      allNodes = scopeNodes ++ allAspectNodes;

      # --- Edges ---

      # Internal aspect edges (per-host).
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

      # Scope hierarchy edges: parent → child for the entire scope tree.
      scopeHierarchyEdges = lib.concatMap (
        scopeId:
        let
          parent = scopeParent.${scopeId} or null;
        in
        lib.optional (parent != null && parent != "__unscoped" && parent != "") {
          from = scopeNodeId parent;
          to = scopeNodeId scopeId;
          style = "normal";
          label = null;
          host = null;
          crossHost = false;
        }
      ) allScopeIds;

      # Host scope → root aspect node edge (connect scope node to the host's root aspect).
      hostRootEdges = lib.concatMap (
        hostName:
        let
          graph = hostGraphs.${hostName} or null;
          hostScopeId = lib.findFirst (
            s: (scopeEntityKind.${s} or null) == "host" && hostNameFromScope s == hostName
          ) null hostScopes;
          rootNodeId = if graph != null then prefixId hostName graph.rootId else null;
        in
        lib.optional (hostScopeId != null && rootNodeId != null) {
          from = scopeNodeId hostScopeId;
          to = rootNodeId;
          style = "normal";
          label = null;
          host = hostName;
          crossHost = false;
        }
      ) (builtins.attrNames hostGraphs);

      # Cross-host pipe flow edges — connect host scope nodes.
      pipeFlowEdges = lib.concatMap (
        pipeName:
        let
          hostScopeOf =
            hName:
            lib.findFirst (
              s: (scopeEntityKind.${s} or null) == "host" && hostNameFromScope s == hName
            ) null hostScopes;
        in
        map (
          flow:
          let
            fromScope = hostScopeOf flow.from;
            toScope = hostScopeOf flow.to;
          in
          {
            from = if fromScope != null then scopeNodeId fromScope else sanitize "host_${flow.from}";
            to = if toScope != null then scopeNodeId toScope else sanitize "host_${flow.to}";
            style = "pipe";
            label = flow.pipeName;
            pipe = flow.pipeName;
            crossHost = true;
            host = null;
          }
        ) (pipes.${pipeName}).flows
      ) allPipeNames;

      allEdges = scopeHierarchyEdges ++ hostRootEdges ++ allInternalEdges ++ pipeFlowEdges;

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
