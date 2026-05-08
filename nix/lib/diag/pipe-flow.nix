# Pipe flow visualization: cross-host quirk data flows.
#
# Takes fleet capture data (from captureFleet) and builds a mermaid
# flowchart showing:
#   - Environment subgraphs grouping hosts
#   - Pipe flow edges (producer → consumer) colored by pipe name
#   - Aspect annotations showing which aspect produces/consumes each pipe
#
# Usage:
#   fleetData = diag.captureFleet {};
#   source = diag.toPipeFlowMermaid fleetData;
{
  lib,
  themes,
  util,
  renderUtil,
}:
let
  inherit (renderUtil) renderMermaid;
  inherit (util) makeIdSanitizer;

  sanitize = makeIdSanitizer "h";

  # Extract host name from a scope ID like "environment=prod,fleet=fleet,host=lb-prod"
  hostNameFromScope =
    scopeId:
    let
      parts = lib.splitString "," scopeId;
      hostPart = lib.findFirst (p: lib.hasPrefix "host=" p) null parts;
    in
    if hostPart != null then lib.removePrefix "host=" hostPart else null;

  # Extract environment name from a scope ID
  envNameFromScope =
    scopeId:
    let
      parts = lib.splitString "," scopeId;
      envPart = lib.findFirst (p: lib.hasPrefix "environment=" p) null parts;
    in
    if envPart != null then lib.removePrefix "environment=" envPart else null;

  # Find siblings of a scope (same parent, same entity kind).
  siblingsOf =
    scopeParent: scopeEntityKind: scopeId:
    let
      parent = scopeParent.${scopeId} or null;
      allScopes = builtins.attrNames scopeParent;
      siblings = builtins.filter (
        s:
        s != scopeId
        && (scopeParent.${s} or null) == parent
        && (scopeEntityKind.${s} or null) == (scopeEntityKind.${scopeId} or null)
      ) allScopes;
    in
    siblings;

  # Build pipe flow data from fleet capture.
  buildPipeFlows =
    fleetCapture:
    let
      inherit (fleetCapture)
        scopeParent
        scopeContexts
        scopeEntityKind
        scopedPipeEffects
        scopedClassImports
        ;

      # Host-level scopes only.
      hostScopes = builtins.filter (s: (scopeEntityKind.${s} or null) == "host") (
        builtins.attrNames scopeEntityKind
      );

      # Environment-level scopes.
      envScopes = builtins.filter (s: (scopeEntityKind.${s} or null) == "environment") (
        builtins.attrNames scopeEntityKind
      );

      # Hosts grouped by environment.
      hostsInEnv = envScope: builtins.filter (h: (scopeParent.${h} or null) == envScope) hostScopes;

      environments = map (
        envScope:
        let
          eName = envNameFromScope envScope;
        in
        {
          name = if eName != null then eName else envScope;
          scope = envScope;
          hosts = map (
            hScope:
            let
              hName = hostNameFromScope hScope;
              classKeys = builtins.attrNames (scopedClassImports.${hScope} or { });
              # Pipe keys this host produces (present in classImports but not a class).
              pipeKeys = builtins.filter (
                k: k != "nixos" && k != "homeManager" && k != "user" && k != "darwin"
              ) classKeys;
              # Pipe effects (pipe.collect) at this scope.
              effects = scopedPipeEffects.${hScope} or [ ];
              collectPipes = lib.unique (
                map (e: e.value.pipeName or e.pipeName or null) (
                  builtins.filter (
                    e: builtins.any (s: (s.__pipeStage or null) == "collect") (e.value.stages or e.stages or [ ])
                  ) effects
                )
              );
            in
            {
              name = if hName != null then hName else hScope;
              scope = hScope;
              produces = pipeKeys;
              collects = builtins.filter (p: p != null) collectPipes;
            }
          ) (hostsInEnv envScope);
        }
      ) envScopes;

      # Build flow edges: for each host that collects a pipe, find siblings
      # that produce it.
      flowEdges = lib.concatMap (
        env:
        lib.concatMap (
          consumer:
          lib.concatMap (
            pipeName:
            let
              producers = builtins.filter (h: builtins.elem pipeName h.produces) env.hosts;
              # Exclude self-collection.
              otherProducers = builtins.filter (h: h.scope != consumer.scope) producers;
            in
            map (producer: {
              from = producer.name;
              to = consumer.name;
              pipe = pipeName;
              environment = env.name;
            }) otherProducers
          ) consumer.collects
        ) env.hosts
      ) environments;
    in
    {
      inherit environments flowEdges;
      # Hosts without an environment (direct children of fleet or flake).
      orphanHosts = builtins.filter (
        h:
        let
          parent = scopeParent.${h} or null;
        in
        parent != null && !builtins.any (e: e.scope == parent) environments
      ) hostScopes;
    };

  # Render pipe flow as mermaid.
  toPipeFlowMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    fleetCapture:
    let
      flows = buildPipeFlows fleetCapture;

      # Unique pipe names for color assignment.
      pipeNames = lib.unique (map (e: e.pipe) flows.flowEdges);
      pipeColors = [
        theme.accent0 or "#f38ba8"
        theme.accent1 or "#fab387"
        theme.accent2 or "#f9e2af"
        theme.accent3 or "#a6e3a1"
        theme.accent4 or "#94e2d5"
        theme.accent5 or "#89b4fa"
        theme.accent6 or "#cba6f7"
        theme.accent7 or "#f2cdcd"
      ];
      pipeColorOf =
        pipeName:
        let
          idx = lib.lists.findFirstIndex (p: p == pipeName) 0 pipeNames;
        in
        builtins.elemAt pipeColors (lib.mod idx (builtins.length pipeColors));

      # All unique host names for node declarations.
      allHostNames = lib.unique (lib.concatMap (env: map (h: h.name) env.hosts) flows.environments);

      # Environment subgraphs.
      envSubgraph =
        env:
        let
          hostDecls = map (
            h:
            let
              produces = if h.produces != [ ] then " (${lib.concatStringsSep ", " h.produces})" else "";
            in
            "    ${sanitize h.name}([\"${h.name}${produces}\"])"
          ) env.hosts;
        in
        "  subgraph ${sanitize "env_${env.name}"}[\"${env.name}\"]\n"
        + lib.concatStringsSep "\n" hostDecls
        + "\n  end";

      # Flow edges grouped by pipe for visual clarity.
      edgesForPipe =
        pipeName:
        let
          edges = builtins.filter (e: e.pipe == pipeName) flows.flowEdges;
          edgeDecl = e: "  ${sanitize e.from} -->|${e.pipe}| ${sanitize e.to}";
        in
        map edgeDecl edges;

      # Link styles for coloring edges by pipe.
      linkStyles =
        let
          allEdgeLines = lib.concatMap edgesForPipe pipeNames;
          edgeIndices = lib.genList (i: i) (builtins.length allEdgeLines);
        in
        lib.imap0 (
          i: _:
          let
            # Find which pipe this edge belongs to by counting edges per pipe.
            edgeCounts = map (p: builtins.length (builtins.filter (e: e.pipe == p) flows.flowEdges)) pipeNames;
            pipeIdx =
              let
                go =
                  remaining: pIdx:
                  if pIdx >= builtins.length edgeCounts then
                    0
                  else if remaining < builtins.elemAt edgeCounts pIdx then
                    pIdx
                  else
                    go (remaining - builtins.elemAt edgeCounts pIdx) (pIdx + 1);
              in
              go i 0;
            color = builtins.elemAt pipeColors (lib.mod pipeIdx (builtins.length pipeColors));
          in
          "  linkStyle ${toString i} stroke:${color},stroke-width:2px"
        ) allEdgeLines;
    in
    if flows.flowEdges == [ ] then
      renderMermaid {
        inherit theme mermaidConfig;
        diagramKind = "graph LR";
      } [ "  note([\"No pipe flows detected\"])" ]
    else
      renderMermaid
        {
          inherit theme mermaidConfig;
          diagramKind = "graph LR";
        }
        (
          map envSubgraph flows.environments
          ++ [ "" ]
          ++ lib.concatMap edgesForPipe pipeNames
          ++ [ "" ]
          ++ linkStyles
          ++ [
            ""
            "  classDef default fill:${theme.nodeBg or "#313244"},stroke:${theme.nodeBorder or "#a6adc8"},color:${theme.nodeText or "#cdd6f4"}"
          ]
          ++ map (
            env:
            "  style ${sanitize "env_${env.name}"} fill:${theme.clusterBg or "#313244"},stroke:${
                theme.clusterBorder or "#6c7086"
              },stroke-width:2px"
          ) flows.environments
        );

  toPipeFlowMermaid = toPipeFlowMermaidWith { };

in
{
  inherit
    buildPipeFlows
    toPipeFlowMermaid
    toPipeFlowMermaidWith
    ;
}
