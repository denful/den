# PlantUML renderer: graph IR → PlantUML string.
#
# Emits `skinparam` directives derived from a theme passed via the
# render opts so the rendered SVG matches the shared palette used by
# mermaid and dot. Theme is render-time, never on the IR.
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
  inherit (renderUtil) skinparamFor visualFor;

  # Element types this renderer emits. Rectangle/Hexagon/Card are filled
  # per-node with an accent color (see `pumlStyle` below — we override the
  # fill at element declaration), so their default font color must be
  # dark (rootText) for readability on bright accent fills. Package/Note
  # inherit the clusterBg palette.
  plantumlElements = [
    "Rectangle"
    "Hexagon"
    "Card"
    "Package"
    "Note"
  ];
  plantumlAccentElements = [
    "Rectangle"
    "Hexagon"
    "Card"
  ];

  toPlantUMLWith =
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
        entityEdges
        ;
      hasEntityKinds = entityKinds != [ ];
      rootColor = theme.rootFill;
      vf = visualFor { inherit theme nodeColorFor; };

      kindSuffix =
        node: if !hasEntityKinds && (node.entityKind or null) != null then " · ${node.entityKind}" else "";

      pumlShape =
        node:
        if node.shape == "hexagon" then
          "hexagon"
        else if node.shape == "trapezoid" then
          "card"
        else
          "rectangle";

      # Escape angle brackets to prevent PlantUML from interpreting
      # <anon> as a stereotype/generic.
      escapePuml = s: builtins.replaceStrings [ "<" ">" ] [ "&lt;" "&gt;" ] s;

      pumlLabel =
        node:
        let
          label = escapePuml node.label;
        in
        if node.isParametric then
          "${label}\\n({ ${fmtArgs node.fnArgNames} })${kindSuffix node}"
        else
          "${label}${kindSuffix node}";

      # PlantUML: `#fill` sets background; `;line.dashed` appends a dashed
      # border. Chaining style directives with `;` is the supported form.
      pumlStyle =
        node:
        let
          v = vf node;
        in
        if v.isExcluded || v.isReplaced then " ${v.fill};line.dashed" else " ${v.fill}";

      nodeDecl = node: "${pumlShape node} \"${pumlLabel node}\" as ${node.id}${pumlStyle node}";

      edgeDecl =
        edge:
        let
          arrow =
            if edge.style == "excluded" then
              "..x"
            else if edge.style == "replaced" then
              "..>"
            else
              "-->";
          label = if edge.label != null then " : ${edge.label}" else "";
        in
        "${edge.from} ${arrow} ${edge.to}${label}";

      entitySubgraph =
        ek:
        let
          ekNodes = builtins.filter (n: n.entityKind == ek.name && n.id != rootId) nodes;
          ctxLabel = if ek.ctxKeys != [ ] then " { ${lib.concatStringsSep ", " ek.ctxKeys} }" else "";
          safeName = builtins.replaceStrings [ "-" " " "/" "." "(" ")" ] [ "_" "_" "__" "_" "_" "_" ] ek.name;
          pkgAlias = "ek_${safeName}";
        in
        lib.optional (ekNodes != [ ]) (
          "package \"${ek.name}${ctxLabel}\" as ${pkgAlias} {\n"
          + lib.concatMapStringsSep "\n" (n: "  ${nodeDecl n}") ekNodes
          + "\n}"
        );
    in
    lib.concatStringsSep "\n" (
      [
        "@startuml"
        "left to right direction"
        (skinparamFor {
          inherit theme;
          elements = plantumlElements;
          onAccentFill = plantumlAccentElements;
        })
        "rectangle \"${rootName}\" as ${rootId} ${rootColor}"
      ]
      ++ lib.concatMap entitySubgraph entityKinds
      ++ map nodeDecl (builtins.filter (n: n.entityKind == null && n.id != rootId) nodes)
      ++ [ "" ]
      ++ map edgeDecl edges
      ++ map edgeDecl entityEdges
      ++ [ "@enduml" ]
    );
  toPlantUML = toPlantUMLWith { };
in
{
  inherit toPlantUML toPlantUMLWith;
}
