# C4 model diagram renderers — PlantUML AND Mermaid flavors.
#
# The C4 model gives us three useful framings of the same data:
#
#   toC4Component graph  — per-host, components = aspects grouped by stage
#   toC4Container graph  — per-host, containers = classes/ctx stages
#   toC4Context fleet    — across-host, systems = hosts, people = users
#
# Two render backends:
#   - PlantUML via C4 stdlib (`!include <C4/C4_*>`) — `to*With`
#   - Mermaid via C4Context/C4Container/C4Component diagrams — `to*MermaidWith`
#
# Both share the same macro-ish body syntax: `Person(...)`, `System(...)`,
# `Rel(...)`, `System_Boundary(...) { ... }`. Only the framing header
# (`@startuml` + include vs mermaid diagramKind + init directive) differs.
{
  lib,
  themes,
  util,
  renderUtil,
}:
let
  inherit (util) meaningful makeIdSanitizer;
  inherit (renderUtil) skinparamFor renderMermaid;

  # C4 stdlib respects standard plantuml skinparams, so we share the
  # render-util primitive with plantuml.nix. C4 uses Person/System/
  # Container/Component/Boundary/Rectangle element types; only Boundary
  # is treated specially (cluster-like palette).
  c4Elements = [
    "Person"
    "System"
    "Container"
    "Component"
    "Boundary"
    "Rectangle"
  ];
  c4Skinparam =
    theme:
    skinparamFor {
      inherit theme;
      elements = c4Elements;
    };

  # C4 identifiers must be plain (alnum + underscore).
  idOf = makeIdSanitizer "c4";

  # Strings inside C4 macros are double-quoted. Escape embedded quotes.
  esc = s: lib.replaceStrings [ "\"" ] [ "\\\"" ] s;

  entityLabel = util.entityLabel { };

  # --- Shared body-builders ---
  #
  # These produce the diagram body lines (without any framing wrapper) in
  # the C4 macro syntax that both PlantUML's C4 stdlib and Mermaid's native
  # C4 diagrams understand. The PlantUML renderers wrap the output in
  # @startuml / !include / @enduml; the Mermaid renderers pass it to
  # renderMermaid.

  # Component view body: aspects grouped by entity kind inside one host.
  # The host becomes a System_Boundary. Each entity kind becomes a
  # Container_Boundary holding its aspects as Components. Aspect inclusions
  # become Rels.
  c4ComponentBody =
    theme: graph:
    let
      inherit (graph)
        rootName
        rootId
        nodes
        edges
        entityKinds
        ;

      aspectNodes = builtins.filter (n: meaningful n.label && n.id != rootId) nodes;
      byEntityKind = ek: builtins.filter (n: n.entityKind == ek.name) aspectNodes;
      unkindedNodes = builtins.filter (n: n.entityKind == null) aspectNodes;

      componentDecl = node: ''Component(${node.id}, "${esc node.label}", "${esc (node.class or "")}")'';

      containerDecl =
        ek:
        let
          members = byEntityKind ek;
          membersStr = lib.concatMapStringsSep "\n    " componentDecl members;
        in
        if members == [ ] then
          null
        else
          ''
            Container_Boundary(${idOf ek.name}, "${esc (entityLabel ek)}") {
                ${membersStr}
            }'';

      containerDecls = builtins.filter (x: x != null) (map containerDecl entityKinds);

      relDecl =
        edge:
        if (edge.style or "normal") == "excluded" then
          ''Rel(${edge.from}, ${edge.to}, "excluded")''
        else if (edge.style or "normal") == "replaced" then
          ''Rel(${edge.from}, ${edge.to}, "replaced")''
        else if (edge.style or "normal") == "provide" then
          ''Rel(${edge.from}, ${edge.to}, "provides")''
        else
          ''Rel(${edge.from}, ${edge.to}, "includes")'';

      keptIds = lib.listToAttrs (
        map (n: {
          name = n.id;
          value = true;
        }) aspectNodes
      );
      renderableEdges = builtins.filter (e: keptIds ? ${e.from} && keptIds ? ${e.to}) edges;
    in
    [
      ''title Component view: ${esc rootName}''
      ""
      ''System_Boundary(${rootId}, "${esc rootName}") {''
    ]
    ++ map (s: "  ${s}") containerDecls
    ++ map componentDecl unkindedNodes
    ++ [
      "}"
      ""
    ]
    ++ map relDecl renderableEdges;

  # Container view body: one box per entity kind / class, no components inside.
  # Each entity kind becomes a Container with a count of aspects it holds.
  # Entity kind transitions become Rels. The host is the System_Boundary.
  c4ContainerBody =
    theme: graph:
    let
      inherit (graph)
        rootName
        rootId
        nodes
        entityKinds
        entityEdges
        ;
      aspectNodes = builtins.filter (n: meaningful n.label && n.id != rootId) nodes;
      entityClassHint =
        ek:
        let
          ekNodes = builtins.filter (n: n.entityKind == ek.name) aspectNodes;
          classes = lib.unique (builtins.filter (c: c != null && c != "") (map (n: n.class or null) ekNodes));
        in
        if classes == [ ] then "mixed" else lib.concatStringsSep "+" classes;

      # Use ek.id for both container declaration and edge endpoints so
      # they line up. ek.id is already a valid C4 identifier.
      containerDecl =
        ek:
        let
          count = builtins.length (builtins.filter (n: n.entityKind == ek.name) aspectNodes);
          desc = "${toString count} aspect${lib.optionalString (count != 1) "s"}";
        in
        ''Container(${ek.id}, "${esc (entityLabel ek)}", "${esc (entityClassHint ek)}", "${desc}")'';

      relDecl =
        edge:
        let
          label = if edge.label != null then edge.label else "resolve";
        in
        ''Rel(${edge.from}, ${edge.to}, "${esc label}")'';
    in
    if entityKinds == [ ] then
      [
        ''title Container view: ${esc rootName}''
        ""
        ''System(${rootId}, "${esc rootName}", "no entity kinds captured")''
      ]
    else
      [
        ''title Container view: ${esc rootName}''
        ""
        ''System_Boundary(${rootId}, "${esc rootName}") {''
      ]
      ++ map (s: "  ${containerDecl s}") entityKinds
      ++ [
        "}"
        ""
      ]
      ++ map relDecl entityEdges;

  # Context view body: fleet-wide overview.
  # Expects a fleet record `{ flakeName, hosts, users, relations }` (built by
  # fleet.nix). Hosts become Systems, users become Persons, and relations
  # (user→host via classes, host→host via cross-provides) become Rels.
  c4ContextBody =
    theme: fleet:
    let
      inherit (fleet)
        flakeName
        hosts
        users
        relations
        ;
      personDecl = user: ''Person(${idOf user.name}, "${esc user.name}")'';
      systemDecl =
        host:
        let
          desc = host.description or "";
        in
        ''System(${idOf host.name}, "${esc host.name}", "${esc desc}")'';
      relDecl = rel: ''Rel(${idOf rel.from}, ${idOf rel.to}, "${esc rel.label}")'';
    in
    [
      ''title ${esc flakeName} — Fleet Context''
      ""
    ]
    ++ map personDecl users
    ++ [ "" ]
    ++ map systemDecl hosts
    ++ [ "" ]
    ++ map relDecl relations;

  # --- PlantUML renderers ---
  #
  # Each renderer calls the corresponding body-builder and wraps the result
  # in PlantUML framing (@startuml, !include <C4/C4_*>, skinparam, @enduml).

  toC4ComponentWith =
    {
      theme ? themes.defaultTheme,
    }:
    graph:
    lib.concatStringsSep "\n" (
      [
        "@startuml"
        "!include <C4/C4_Component>"
        (c4Skinparam theme)
        ""
      ]
      ++ c4ComponentBody theme graph
      ++ [ "@enduml" ]
    );

  toC4ContainerWith =
    {
      theme ? themes.defaultTheme,
    }:
    graph:
    let
      body = c4ContainerBody theme graph;
    in
    lib.concatStringsSep "\n" (
      [
        "@startuml"
        "!include <C4/C4_Container>"
        (c4Skinparam theme)
        ""
      ]
      ++ body
      ++ [ "@enduml" ]
    );

  toC4ContextWith =
    {
      theme ? themes.defaultTheme,
    }:
    fleet:
    lib.concatStringsSep "\n" (
      [
        "@startuml"
        "!include <C4/C4_Context>"
        (c4Skinparam theme)
        ""
      ]
      ++ c4ContextBody theme fleet
      ++ [
        ""
        "@enduml"
      ]
    );

  # --- Mermaid renderers ---
  #
  # Mermaid natively supports C4 diagrams (`C4Context`, `C4Container`,
  # `C4Component`) with the same macro body syntax as PlantUML's C4
  # stdlib. The body-builder helpers above already produce that syntax;
  # we just wrap them in a mermaid init directive + diagram header
  # instead of `@startuml` + `!include`.
  #
  # Mermaid C4 doesn't respect skinparam directives — theme colors come
  # from the init directive's `themeVariables`, which our
  # `mermaidFrontmatter` already sets per-theme.

  toC4ComponentMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    graph:
    renderMermaid {
      inherit theme mermaidConfig;
      diagramKind = "C4Component";
    } (c4ComponentBody theme graph);

  toC4ContainerMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    graph:
    renderMermaid {
      inherit theme mermaidConfig;
      diagramKind = "C4Container";
    } (c4ContainerBody theme graph);

  toC4ContextMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    fleet:
    renderMermaid {
      inherit theme mermaidConfig;
      diagramKind = "C4Context";
    } (c4ContextBody theme fleet);

  toC4Component = toC4ComponentWith { };
  toC4Container = toC4ContainerWith { };
  toC4Context = toC4ContextWith { };
  toC4ComponentMermaid = toC4ComponentMermaidWith { };
  toC4ContainerMermaid = toC4ContainerMermaidWith { };
  toC4ContextMermaid = toC4ContextMermaidWith { };
in
{
  inherit
    toC4Component
    toC4ComponentWith
    toC4Container
    toC4ContainerWith
    toC4Context
    toC4ContextWith
    toC4ComponentMermaid
    toC4ComponentMermaidWith
    toC4ContainerMermaid
    toC4ContainerMermaidWith
    toC4ContextMermaid
    toC4ContextMermaidWith
    ;
}
