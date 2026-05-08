# Fleet-level visualizations from captureFleet data.
#
# Three views:
#   - Pipe flow: cross-host quirk data flows with environment subgraphs
#   - Scope topology: fleet → environment → host → user resolution tree
#   - Aspect matrix: which aspects land on which hosts
#
# All take captureFleet output as input.
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
              # Use trace-level pipeProducers when available for accurate
              # aspect-level production tracking.
              tracedProducers = fleetCapture.pipeProducers or [ ];
              pipeKeys =
                if tracedProducers != [ ] then
                  lib.unique (map (p: p.pipeName) (builtins.filter (p: p.scope == hScope) tracedProducers))
                else
                  let
                    classKeys = builtins.attrNames (scopedClassImports.${hScope} or { });
                  in
                  builtins.filter (k: k != "nixos" && k != "homeManager" && k != "user" && k != "darwin") classKeys;
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
      # that produce it. Only show a host as a meaningful collector if it
      # does NOT also produce the same pipe (indicating it has a consumer
      # aspect like haproxy). Exception: when ALL collectors also produce
      # (bidirectional pattern like host-addrs), show all edges.
      flowEdges = lib.concatMap (
        env:
        lib.concatMap (
          pipeName:
          let
            producers = builtins.filter (h: builtins.elem pipeName h.produces) env.hosts;
            collectors = builtins.filter (h: builtins.elem pipeName h.collects) env.hosts;
            # Pure consumers: collect but don't produce.
            pureConsumers = builtins.filter (h: !builtins.elem pipeName h.produces) collectors;
            # If no pure consumers exist, it's bidirectional (all produce+collect).
            effectiveConsumers = if pureConsumers != [ ] then pureConsumers else collectors;
          in
          lib.concatMap (
            consumer:
            let
              # Exclude self-collection.
              otherProducers = builtins.filter (h: h.scope != consumer.scope) producers;
            in
            map (producer: {
              from = producer.name;
              to = consumer.name;
              pipe = pipeName;
              environment = env.name;
            }) otherProducers
          ) effectiveConsumers
        ) (lib.unique (lib.concatMap (h: h.collects) env.hosts))
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
          tracedProducers = fleetCapture.pipeProducers or [ ];
          hostDecls = map (
            h:
            let
              # Show producing aspect:pipe pairs for richer labels.
              aspectPipes =
                if tracedProducers != [ ] then
                  let
                    hostProds = builtins.filter (p: p.scope == h.scope) tracedProducers;
                  in
                  map (p: "${p.aspectIdentity}→${p.pipeName}") hostProds
                else
                  h.produces;
              annotation = if aspectPipes != [ ] then " (${lib.concatStringsSep ", " aspectPipes})" else "";
            in
            "    ${sanitize h.name}([\"${h.name}${annotation}\"])"
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

  # --- View 2: Scope topology ---
  #
  # Renders the fleet scope tree as a top-down flowchart:
  #   fleet → environment:prod → host:lb-prod → user:deploy
  #                             → host:web-prod-1 → user:deploy
  #           environment:staging → host:web-staging → user:deploy

  # Extract a human-readable label from a scope ID.
  scopeLabel =
    scopeEntityKind: scopeId:
    let
      kind = scopeEntityKind.${scopeId} or null;
      parts = lib.splitString "," scopeId;
      # Find the part matching this scope's entity kind.
      kindPart = if kind != null then lib.findFirst (p: lib.hasPrefix "${kind}=" p) null parts else null;
      name = if kindPart != null then lib.removePrefix "${kind}=" kindPart else scopeId;
    in
    if kind != null then "${kind}: ${name}" else scopeId;

  toScopeTopologyMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    fleetCapture:
    let
      inherit (fleetCapture) scopeParent scopeEntityKind;

      # All scopes except the unscoped root.
      allScopes = builtins.filter (s: s != "__unscoped" && s != "") (builtins.attrNames scopeParent);

      # Build nodes and edges from scope tree.
      nodeDecl =
        scopeId:
        let
          kind = scopeEntityKind.${scopeId} or null;
          label = scopeLabel scopeEntityKind scopeId;
          shape =
            if kind == "fleet" then
              "([\"${label}\"])"
            else if kind == "environment" then
              "[[\"${label}\"]]"
            else if kind == "host" then
              "[\"${label}\"]"
            else if kind == "user" then
              "([\"${label}\"])"
            else
              "[\"${label}\"]";
        in
        "  ${sanitize scopeId}${shape}";

      edgeDecl =
        scopeId:
        let
          parent = scopeParent.${scopeId} or null;
        in
        lib.optional (
          parent != null && parent != "__unscoped" && parent != ""
        ) "  ${sanitize parent} --> ${sanitize scopeId}";

      # Color nodes by entity kind.
      kindColors = {
        fleet = theme.accent5 or "#89b4fa";
        environment = theme.accent6 or "#cba6f7";
        host = theme.accent3 or "#a6e3a1";
        user = theme.accent1 or "#fab387";
        "flake-system" = theme.accent4 or "#94e2d5";
      };
      nodeStyle =
        scopeId:
        let
          kind = scopeEntityKind.${scopeId} or null;
          color = kindColors.${kind} or (theme.nodeBg or "#313244");
          text = theme.rootText or "#1e1e2e";
        in
        "  style ${sanitize scopeId} fill:${color},stroke:${color},color:${text}";
    in
    renderMermaid
      {
        inherit theme mermaidConfig;
        diagramKind = "graph TD";
      }
      (
        map nodeDecl allScopes
        ++ [ "" ]
        ++ lib.concatMap edgeDecl allScopes
        ++ [ "" ]
        ++ map nodeStyle allScopes
      );

  toScopeTopologyMermaid = toScopeTopologyMermaidWith { };

  # --- View 3: Aspect coverage matrix ---
  #
  # Renders a table showing which meaningful aspects land on which hosts.
  # Uses mermaid block-beta for a grid layout.
  #
  # Falls back to a simple flowchart with host subgraphs containing
  # their aspects, since mermaid block-beta has limited support.

  toAspectMatrixMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    fleetCapture:
    let
      inherit (fleetCapture) entries scopeEntityKind;

      # Host-level scopes.
      hostScopes = builtins.filter (s: (scopeEntityKind.${s} or null) == "host") (
        builtins.attrNames scopeEntityKind
      );

      # For each host scope, collect meaningful aspect names.
      hostAspects = map (
        hScope:
        let
          hName = hostNameFromScope hScope;
          # Filter entries belonging to this host's instance.
          hostInstance = "host:${hName}";
          hostEntries = builtins.filter (
            e:
            (e.entityInstance or null) == hostInstance
            && (e.hasClass or false)
            && !(e.isPolicyDispatch or false)
            && (e.provider or [ ]) == [ ]
            && e.name != "host"
            && e.name != "user"
            && e.name != "default"
            && !(lib.hasPrefix "<" (e.name or ""))
          ) entries;
          aspectNames = lib.unique (lib.sort (a: b: a < b) (map (e: e.name) hostEntries));
        in
        {
          name = if hName != null then hName else hScope;
          aspects = aspectNames;
        }
      ) hostScopes;

      # All unique aspect names across all hosts.
      allAspects = lib.unique (lib.sort (a: b: a < b) (lib.concatMap (h: h.aspects) hostAspects));

      # Render as a flowchart with one subgraph per host listing its aspects.
      hostSubgraph =
        h:
        let
          aspectNodes = map (
            a:
            let
              present = builtins.elem a h.aspects;
            in
            if present then "    ${sanitize "${h.name}_${a}"}[\"${a}\"]" else null
          ) allAspects;
          filtered = builtins.filter (x: x != null) aspectNodes;
        in
        "  subgraph ${sanitize "host_${h.name}"}[\"${h.name}\"]\n"
        + lib.concatStringsSep "\n" filtered
        + "\n  end";

      # Style aspect nodes — same aspect on different hosts gets the same color.
      aspectColor =
        aspectName:
        let
          idx = lib.lists.findFirstIndex (a: a == aspectName) 0 allAspects;
          colors = [
            (theme.accent0 or "#f38ba8")
            (theme.accent1 or "#fab387")
            (theme.accent2 or "#f9e2af")
            (theme.accent3 or "#a6e3a1")
            (theme.accent4 or "#94e2d5")
            (theme.accent5 or "#89b4fa")
            (theme.accent6 or "#cba6f7")
            (theme.accent7 or "#f2cdcd")
          ];
        in
        builtins.elemAt colors (lib.mod idx (builtins.length colors));

      nodeStyles = lib.concatMap (
        h:
        map (
          a:
          let
            color = aspectColor a;
            text = theme.rootText or "#1e1e2e";
          in
          "  style ${sanitize "${h.name}_${a}"} fill:${color},stroke:${color},color:${text}"
        ) (builtins.filter (a: builtins.elem a h.aspects) allAspects)
      ) hostAspects;

      hostStyles = map (
        h:
        "  style ${sanitize "host_${h.name}"} fill:${theme.clusterBg or "#313244"},stroke:${
            theme.clusterBorder or "#6c7086"
          },stroke-width:2px"
      ) hostAspects;

      # Link same aspects across hosts with dotted edges for visual grouping.
      crossHostLinks = lib.concatMap (
        a:
        let
          hostsWithAspect = builtins.filter (h: builtins.elem a h.aspects) hostAspects;
          pairs =
            if builtins.length hostsWithAspect < 2 then
              [ ]
            else
              let
                first = builtins.head hostsWithAspect;
                rest = builtins.tail hostsWithAspect;
              in
              map (h: {
                from = sanitize "${first.name}_${a}";
                to = sanitize "${h.name}_${a}";
              }) rest;
        in
        map (p: "  ${p.from} -..- ${p.to}") pairs
      ) allAspects;
    in
    renderMermaid {
      inherit theme mermaidConfig;
      diagramKind = "graph LR";
    } (map hostSubgraph hostAspects ++ [ "" ] ++ crossHostLinks ++ [ "" ] ++ nodeStyles ++ hostStyles);

  toAspectMatrixMermaid = toAspectMatrixMermaidWith { };

  # --- View 4: Policy entity resolution map ---
  #
  # Shows the fleet scope tree annotated with which policies drive each
  # entity transition: fleet → environment (via fleet-to-envs) → host
  # (via env-to-hosts) → user (via host-to-users).

  toPolicyResolutionMapMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    fleetCapture:
    let
      inherit (fleetCapture)
        entries
        scopeParent
        scopeEntityKind
        ;

      # Policy entries grouped by entity kind they fire at.
      policyEntries = builtins.filter (e: e.isPolicyDispatch or false) entries;

      # For each scope transition (parent → child), find the policy that
      # fires at the parent scope and creates child scopes of the child's kind.
      # The policy's `from` matches the parent's entity kind.
      policiesAtKind =
        kind: lib.unique (map (e: e.name) (builtins.filter (e: (e.from or null) == kind) policyEntries));

      allScopes = builtins.filter (s: s != "__unscoped" && s != "") (builtins.attrNames scopeParent);

      # Group scopes by parent for fan-out display.
      childrenOf =
        parent:
        lib.sort (a: b: a < b) (builtins.filter (s: (scopeParent.${s} or null) == parent) allScopes);

      # Build nodes with entity-kind-specific shapes.
      nodeDecl =
        scopeId:
        let
          kind = scopeEntityKind.${scopeId} or null;
          label = scopeLabel scopeEntityKind scopeId;
          shape =
            if kind == "fleet" then
              "([\"${label}\"])"
            else if kind == "environment" then
              "{{\"${label}\"}}"
            else if kind == "host" then
              "[\"${label}\"]"
            else if kind == "user" then
              "([\"${label}\"])"
            else
              "[\"${label}\"]";
        in
        "  ${sanitize scopeId}${shape}";

      # Build edges annotated with the policy that drives the transition.
      edgeDecl =
        scopeId:
        let
          parent = scopeParent.${scopeId} or null;
          parentKind = if parent != null then scopeEntityKind.${parent} or null else null;
          policies = if parentKind != null then policiesAtKind parentKind else [ ];
          policyLabel = if policies != [ ] then lib.concatStringsSep ", " policies else null;
          arrow = if policyLabel != null then "-->|${policyLabel}|" else "-->";
        in
        lib.optional (
          parent != null && parent != "__unscoped" && parent != ""
        ) "  ${sanitize parent} ${arrow} ${sanitize scopeId}";

      # Color by entity kind.
      kindColors = {
        fleet = theme.accent5 or "#89b4fa";
        environment = theme.accent6 or "#cba6f7";
        host = theme.accent3 or "#a6e3a1";
        user = theme.accent1 or "#fab387";
        "flake-system" = theme.accent4 or "#94e2d5";
      };
      nodeStyle =
        scopeId:
        let
          kind = scopeEntityKind.${scopeId} or null;
          color = kindColors.${kind} or (theme.nodeBg or "#313244");
          text = theme.rootText or "#1e1e2e";
        in
        "  style ${sanitize scopeId} fill:${color},stroke:${color},color:${text}";
    in
    renderMermaid
      {
        inherit theme mermaidConfig;
        diagramKind = "graph TD";
      }
      (
        map nodeDecl allScopes
        ++ [ "" ]
        ++ lib.concatMap edgeDecl allScopes
        ++ [ "" ]
        ++ map nodeStyle allScopes
      );

  toPolicyResolutionMapMermaid = toPolicyResolutionMapMermaidWith { };

  # --- View 5: Pipe sequence diagram ---
  #
  # Shows quirk production and collection as a sequence diagram.
  # Hosts are participants, grouped by environment via boxes.
  # Emissions are notes, collections are arrows.

  toPipeSequenceMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    fleetCapture:
    let
      flows = buildPipeFlows fleetCapture;
      tracedProducers = fleetCapture.pipeProducers or [ ];

      # All hosts across all environments, ordered by environment.
      allHosts = lib.concatMap (env: env.hosts) flows.environments;

      # Participant declarations grouped by environment.
      envBoxes = lib.concatMap (
        env:
        let
          hostDecls = map (h: "    participant ${sanitize h.name} as ${h.name}") env.hosts;
        in
        [ "    box ${env.name}" ] ++ hostDecls ++ [ "    end" ]
      ) flows.environments;

      # Per-pipe blocks: emission notes then collection arrows.
      pipeBlock =
        pipeName:
        let
          # Find producing hosts and their aspects from trace data.
          producersByHost = lib.foldl' (
            acc: p:
            let
              hName = hostNameFromScope p.scope;
            in
            if hName != null then
              acc // { ${hName} = lib.unique ((acc.${hName} or [ ]) ++ [ p.aspectIdentity ]); }
            else
              acc
          ) { } (builtins.filter (p: p.pipeName == pipeName) tracedProducers);

          producerHosts = builtins.attrNames producersByHost;

          # Emission notes.
          emissionNotes = map (
            hName:
            let
              aspects = producersByHost.${hName};
            in
            "    Note over ${sanitize hName}: ${lib.concatStringsSep ", " aspects} → ${pipeName}"
          ) producerHosts;

          # Collection arrows from flow edges.
          pipeEdges = builtins.filter (e: e.pipe == pipeName) flows.flowEdges;
          collectionArrows = map (e: "    ${sanitize e.from} -->> ${sanitize e.to}: ${pipeName}") pipeEdges;
        in
        lib.optional (emissionNotes != [ ] || collectionArrows != [ ]) ""
        ++ emissionNotes
        ++ collectionArrows;

      pipeNames = lib.unique (map (p: p.pipeName) tracedProducers ++ map (e: e.pipe) flows.flowEdges);
    in
    if allHosts == [ ] then
      renderMermaid {
        inherit theme mermaidConfig;
        diagramKind = "sequenceDiagram";
      } [ "    participant none as No hosts" ]
    else
      renderMermaid {
        inherit theme mermaidConfig;
        diagramKind = "sequenceDiagram";
      } (envBoxes ++ lib.concatMap pipeBlock pipeNames);

  toPipeSequenceMermaid = toPipeSequenceMermaidWith { };

  # --- View 6: Fleet-wide DAG ---
  #
  # Composes all hosts' aspect trees into a single DAG with:
  #   - Environment subgraphs containing host subgraphs
  #   - Per-host aspects inside their host subgraph
  #   - Cross-host pipe flow edges
  #   - User scopes nested under their host
  #
  # Takes fleet capture data + a function to build per-host graphs.
  toFleetDagMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    {
      fleetCapture,
      hostGraphs, # attrset: { "lb-prod" = graphIR; "web-prod-1" = graphIR; ... }
    }:
    let
      flows = buildPipeFlows fleetCapture;
      tracedProducers = fleetCapture.pipeProducers or [ ];

      # Prefix all node/edge IDs with the host name to avoid collisions
      # across hosts (e.g., "default" exists on every host).
      prefixId = hostName: id: "${sanitize hostName}__${id}";

      # Build per-host subgraph content.
      hostBlock =
        hostName: graph:
        let
          meaningful = builtins.filter (
            n:
            (n.hasClass or false)
            && !(n.isPolicyDispatch or false)
            && !(lib.hasPrefix "<" n.label)
            && n.label != "host"
            && n.label != "user"
            && n.label != "default"
          ) graph.nodes;

          nodeDecl =
            n:
            let
              shape =
                if n.shape == "hexagon" then
                  "{{\"${n.label}\"}}"
                else if n.shape == "trapezoid" then
                  "[/\"${n.label}\"\\]"
                else
                  "[\"${n.label}\"]";
            in
            "      ${prefixId hostName n.id}${shape}";

          # Internal edges within this host.
          internalEdges = builtins.filter (
            e:
            let
              fromNode = lib.findFirst (n: n.id == e.from) null graph.nodes;
              toNode = lib.findFirst (n: n.id == e.to) null graph.nodes;
            in
            fromNode != null
            && toNode != null
            && (fromNode.hasClass or false)
            && (toNode.hasClass or false)
            && !(fromNode.isPolicyDispatch or false)
            && !(toNode.isPolicyDispatch or false)
            && (e.style or "normal") == "normal"
          ) graph.edges;

          edgeDecl = e: "      ${prefixId hostName e.from} --> ${prefixId hostName e.to}";
        in
        if meaningful == [ ] then
          [ ]
        else
          [
            "    subgraph ${sanitize "host_${hostName}"}[\"${hostName}\"]"
          ]
          ++ map nodeDecl (lib.sort (a: b: a.label < b.label) meaningful)
          ++ map edgeDecl internalEdges
          ++ [ "    end" ];

      # Environment subgraphs containing host subgraphs.
      envBlock =
        env:
        let
          hostBlocks = lib.concatMap (
            h:
            let
              graph = hostGraphs.${h.name} or null;
            in
            if graph != null then hostBlock h.name graph else [ ]
          ) env.hosts;
        in
        if hostBlocks == [ ] then
          [ ]
        else
          [ "  subgraph ${sanitize "env_${env.name}"}[\"${env.name}\"]" ] ++ hostBlocks ++ [ "  end" ];

      # Pipe flow edges between hosts (cross-host only).
      pipeEdges = map (
        e: "  ${sanitize "host_${e.from}"} -->|${e.pipe}| ${sanitize "host_${e.to}"}"
      ) flows.flowEdges;

      # Host subgraph styles.
      hostStyles = lib.concatMap (
        env:
        map (
          h:
          "  style ${sanitize "host_${h.name}"} fill:${theme.nodeBg or "#313244"},stroke:${theme.nodeBorder or "#a6adc8"},stroke-width:1px"
        ) env.hosts
      ) flows.environments;

      envStyles = map (
        env:
        "  style ${sanitize "env_${env.name}"} fill:${theme.clusterBg or "#313244"},stroke:${
            theme.clusterBorder or "#6c7086"
          },stroke-width:2px"
      ) flows.environments;
    in
    renderMermaid
      {
        inherit theme mermaidConfig;
        diagramKind = "graph LR";
      }
      (
        lib.concatMap envBlock flows.environments
        ++ [ "" ]
        ++ pipeEdges
        ++ [ "" ]
        ++ hostStyles
        ++ envStyles
      );

  toFleetDagMermaid = toFleetDagMermaidWith { };

in
{
  inherit
    buildPipeFlows
    toPipeFlowMermaid
    toPipeFlowMermaidWith
    toScopeTopologyMermaid
    toScopeTopologyMermaidWith
    toAspectMatrixMermaid
    toAspectMatrixMermaidWith
    toPolicyResolutionMapMermaid
    toPolicyResolutionMapMermaidWith
    toPipeSequenceMermaid
    toPipeSequenceMermaidWith
    toFleetDagMermaid
    toFleetDagMermaidWith
    ;
}
