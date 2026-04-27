# Graphviz DOT renderer: graph IR → DOT string.
#
# Emits graph / node / edge defaults from the theme passed in render
# opts so the result matches the shared palette used by mermaid and
# plantuml. Theme is render-time, never on the IR.
{
  lib,
  themes,
  colors,
  util,
  renderUtil,
}:
let
  inherit (colors) nodeColorFor;
  inherit (util) fmtArgs;
  inherit (renderUtil) visualFor;

  toDotWith =
    {
      theme ? themes.defaultTheme,
    }:
    graph:
    let
      inherit (graph)
        rootName
        rootId
        nodes
        edges
        entityKinds
        direction
        ;
      hasEntityKinds = entityKinds != [ ];
      rootColor = theme.rootFill;
      vf = visualFor { inherit theme nodeColorFor; };

      # When the graph is flat, append the node's stage to the label
      # (matches mermaid.nix `kindSuffix`).
      kindSuffix =
        node: if !hasEntityKinds && (node.entityKind or null) != null then " · ${node.entityKind}" else "";

      dotShape =
        node:
        if node.shape == "hexagon" then
          "hexagon"
        else if node.shape == "trapezoid" then
          "trapezium"
        else
          "box";

      # Excluded/replaced nodes still get their per-node accent fill;
      # the dashed stroke style + red/orange border color carries the
      # "disabled" semantic. See render-util.nix visualFor.
      dotStyle =
        node:
        let
          v = vf node;
          styleAttr = if v.isExcluded || v.isReplaced then ''"filled,dashed"'' else "filled";
        in
        ''style=${styleAttr},fillcolor="${v.fill}",color="${v.stroke}",fontcolor="${v.text}"'';

      dotLabel =
        node:
        if node.isParametric then
          "${node.label}\\n({ ${fmtArgs node.fnArgNames} })${kindSuffix node}"
        else
          "${node.label}${kindSuffix node}";

      nodeDecl =
        node:
        let
          attrs = lib.concatStringsSep "," [
            ''label="${dotLabel node}"''
            "shape=${dotShape node}"
            (dotStyle node)
          ];
        in
        "  ${node.id} [${attrs}];";

      edgeDecl =
        edge:
        let
          attrs =
            if edge.style == "excluded" then
              " [style=dashed,color=\"${theme.excludedStroke}\"]"
            else if edge.style == "replaced" then
              " [style=dashed,color=\"${theme.replacedStroke}\",label=\"replaced\"]"
            else
              "";
        in
        "  ${edge.from} -> ${edge.to}${attrs};";

      entitySubgraph =
        ek:
        let
          ekNodes = builtins.filter (n: n.entityKind == ek.name && n.id != rootId) nodes;
          ctxLabel = if ek.ctxKeys != [ ] then " { ${lib.concatStringsSep ", " ek.ctxKeys} }" else "";
        in
        lib.optional (ekNodes != [ ]) (
          "  subgraph cluster_${ek.id} {\n"
          + "    label=\"${ek.name}${ctxLabel}\";\n"
          + "    style=dashed;\n"
          + "    color=\"${theme.clusterBorder}\";\n"
          + "    fontcolor=\"${theme.foreground}\";\n"
          + "    bgcolor=\"${theme.clusterBg}\";\n"
          + lib.concatMapStringsSep "\n" nodeDecl ekNodes
          + "\n  }"
        );

      dotDir = if direction == "LR" then "LR" else "TB";
    in
    lib.concatStringsSep "\n" (
      [
        "digraph {"
        "  rankdir=${dotDir};"
        "  bgcolor=\"${theme.background}\";"
        "  color=\"${theme.foreground}\";"
        "  fontcolor=\"${theme.foreground}\";"
        "  node [style=filled, fillcolor=\"${theme.nodeBg}\", fontcolor=\"${theme.nodeText}\", color=\"${theme.nodeBorder}\"];"
        "  edge [color=\"${theme.edgeColor}\", fontcolor=\"${theme.edgeText}\"];"
        # Stadium-ish rounded rectangle for the host. DOT has no stadium shape.
        "  ${rootId} [label=\"${rootName}\",shape=box,style=\"rounded,filled\",fillcolor=\"${rootColor}\",color=\"${theme.rootStroke}\",fontcolor=\"${theme.rootText}\"];"
      ]
      ++ lib.concatMap entitySubgraph entityKinds
      ++ map nodeDecl (builtins.filter (n: n.entityKind == null && n.id != rootId) nodes)
      ++ [ "" ]
      ++ map edgeDecl edges
      # Stage transitions are not emitted: they would reference cluster names,
      # which DOT cannot use as edge endpoints without lhead/ltail anchor tricks.
      ++ [ "}" ]
    );
  toDot = toDotWith { };
in
{
  inherit toDot toDotWith;
}
