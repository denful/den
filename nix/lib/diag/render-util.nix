# Renderer-level primitives shared across mermaid / plantuml / c4.
#
# Everything here reads a theme — it's render-time. The graph IR never
# touches anything in this file.
{ lib, themes }:
let
  inherit (themes) mermaidFrontmatter;

  # Prepend mermaid init-directive frontmatter + diagram keyword onto a
  # list of body lines and join with newlines. Every mermaid renderer
  # (flowchart, sequence, sankey, ishikawa, treemap) funnels through here.
  #
  # diagramKind examples: "graph LR", "sequenceDiagram", "sankey-beta",
  # "ishikawa-beta", "treemap-beta".
  renderMermaid =
    {
      theme,
      mermaidConfig ? { },
      diagramKind,
    }:
    bodyLines:
    lib.concatStringsSep "\n" (
      [
        (mermaidFrontmatter theme mermaidConfig)
        diagramKind
      ]
      ++ bodyLines
    );

  # Canonical palette-to-skinparam mapping. Takes a theme and a list of
  # element types (e.g. [ "Rectangle" "Hexagon" "Card" ]) and emits the
  # three `*BackgroundColor` / `*BorderColor` / `*FontColor` directives
  # per element plus a shared header (background / fonts / arrows).
  #
  # Three classes of element:
  #
  #   boundaryLike  — Boundary / Package / Note: clusterBg fill, foreground text
  #   onAccentFill  — element types the caller fills per-node with an accent
  #                    color (e.g. plain plantuml's Rectangle/Hexagon/Card).
  #                    skinparam background is irrelevant for these but still
  #                    emitted for parser sanity; the font color must be dark
  #                    (rootText = base16 base00) to be readable on bright
  #                    accent fills.
  #   default       — everything else (C4's Person/System/Container/Component):
  #                    nodeBg fill, nodeText (light on dark theme) — the
  #                    PlantUML macros control these, not per-node styles.
  skinparamFor =
    {
      theme,
      elements,
      onAccentFill ? [ ],
    }:
    let
      boundaryLike = [
        "Boundary"
        "Package"
        "Note"
      ];
      elementBlock =
        el:
        let
          isBoundary = builtins.elem el boundaryLike;
          isAccent = builtins.elem el onAccentFill;
          bg = if isBoundary then theme.clusterBg else theme.nodeBg;
          border = if isBoundary then theme.clusterBorder else theme.nodeBorder;
          fg =
            if isAccent then
              theme.rootText
            else if isBoundary then
              theme.foreground
            else
              theme.nodeText;
        in
        ''
          skinparam ${el}BackgroundColor ${bg}
          skinparam ${el}BorderColor ${border}
          skinparam ${el}FontColor ${fg}
        '';
      header = ''
        skinparam backgroundColor ${theme.background}
        skinparam defaultFontColor ${theme.foreground}
        skinparam defaultFontName "JetBrains Mono,monospace"
        skinparam arrowColor ${theme.edgeColor}
        skinparam arrowFontColor ${theme.edgeText}
      '';
    in
    header + lib.concatStrings (map elementBlock elements);

  # Map a node's style ("excluded" / "replaced" / "adapter" / "default") to
  # a renderer-neutral visual record. Each renderer formats the record in
  # its native syntax but no longer duplicates the style→color decision.
  #
  # `nodeColorFor` is passed in (not imported) so render-util doesn't pull
  # on colors.nix — keeps the dependency shape shallow.
  #
  # Color policy: EVERY node fills with its per-node accent, including
  # excluded/replaced. That way excluded/replaced nodes stay visually
  # distinct from each other (instead of all collapsing onto a single
  # flat red or orange). The "excluded" / "replaced" semantic is carried
  # by the stroke color (excludedStroke = base08 red, replacedStroke =
  # base09 orange) + a dashed border. Only the border signals state; the
  # fill preserves identity.
  visualFor =
    { theme, nodeColorFor }:
    node:
    let
      isExcluded = node.style == "excluded";
      isReplaced = node.style == "replaced";
      isAdapter = node.style == "adapter";
      isTerminal = node.style == "terminal";
      isPolicy = node.style == "policy";
      isDefault = !(isExcluded || isReplaced || isAdapter || isTerminal || isPolicy);
      accent = nodeColorFor theme (node.entityKind or null) node.label;
    in
    {
      inherit
        isExcluded
        isReplaced
        isAdapter
        isTerminal
        isPolicy
        isDefault
        ;
      fill = if isTerminal then theme.clusterBg else accent;
      stroke =
        if isExcluded then
          theme.excludedStroke
        else if isReplaced then
          theme.replacedStroke
        else if isTerminal then
          theme.clusterBorder
        else
          accent;
      text = if isTerminal then theme.foreground else theme.rootText;
      strokeStyle =
        if isExcluded || isReplaced then
          "dashed"
        else if isTerminal then
          "dotted"
        else
          "solid";
    };
  # Creates a { toFoo, toFooWith } pair from a *With function.
  # withFn already has defaults for all its args, so `withFn {}` works.
  mkRenderer = name: withFn: {
    "${name}With" = withFn;
    ${name} = withFn { };
  };
in
{
  inherit
    renderMermaid
    skinparamFor
    visualFor
    mkRenderer
    ;
}
