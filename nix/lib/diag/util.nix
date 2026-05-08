# Shared graph-level primitives used by graph.nix and the renderers.
#
# Everything in here is pure data manipulation. No theme, no color, no
# render-time concerns — those live in render-util.nix.
{ lib }:
let
  # Drop list entries whose key (derived by keyFn) has been seen before.
  # Preserves input order.
  dedupBy =
    keyFn: items:
    (builtins.foldl'
      (
        acc: item:
        let
          k = keyFn item;
        in
        if acc.seen ? ${k} then
          acc
        else
          {
            seen = acc.seen // {
              ${k} = true;
            };
            result = acc.result ++ [ item ];
          }
      )
      {
        seen = { };
        result = [ ];
      }
      items
    ).result;

  # Comma-join a list of arg names. Used by renderers that format
  # parametric aspect fnArgNames as a function signature hint.
  fmtArgs = names: if names == [ ] then "" else lib.concatStringsSep ", " names;

  # Shared filter: drops anonymous nodes, function bodies, and module-merge
  # definition artifacts. These are structurally uninteresting to every
  # renderer that cares about user-visible aspects.
  meaningful =
    name: name != "<anon>" && name != "<function body>" && !(lib.hasPrefix "[definition " name);

  # Context-pipeline scaffolding predicate. Matches node labels produced by
  # aspect resolution machinery (`foo/aspect`, `foo/self-provide`, etc.) —
  # not things a user wrote. Used by foldWrappers and by renderers that want
  # to hide pipeline plumbing behind user aspects.
  isWrapper = label: builtins.match ".+/(aspect|self-provide|cross-provide|resolve).*" label != null;

  # A node is a "user aspect" if it's meaningful, not a wrapper, and not the
  # host root. Renderers that suppress plumbing in aspect-level views share
  # this predicate instead of each redefining it.
  isUserAspect = graph: n: meaningful n.label && !(isWrapper n.label) && n.id != (graph.rootId or "");

  # Mermaid flowchart + sequenceDiagram reserved words. A bare identifier
  # matching one of these confuses the parser (e.g. `class` collides with
  # the `classDef` keyword, `end` closes a subgraph block).
  mermaidReservedIds = [
    "class"
    "classDef"
    "classDiagram"
    "click"
    "default"
    "direction"
    "end"
    "flowchart"
    "graph"
    "link"
    "linkStyle"
    "note"
    "participant"
    "style"
    "subgraph"
  ];

  # Plain character sanitization, no prefix. Used for the char-level
  # normalization step when a caller wants to build an identifier with
  # its own fixed prefix (e.g. `ctx_<name>` for stage ids).
  #
  # `/` (the den provider separator) becomes `__` so `a/b` stays distinct
  # from `a_b`. All other delimiters collapse to `_`.
  sanitizeChars =
    s:
    lib.replaceStrings
      [
        "/"
        "-"
        " "
        "."
        "@"
        "~"
        "<"
        ">"
        "["
        "]"
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
        "_"
        "_"
        "_"
        "_"
      ]
      s;

  # Build an identifier sanitizer parameterized by prefix.
  #
  # The `<prefix>_` is only prepended when the sanitized form collides
  # with a mermaid reserved word, is empty, or starts with a digit. Most
  # identifiers pass through cleanly: `boot/systemd` becomes
  # `boot__systemd` rather than `n_boot__systemd`, which makes raw
  # mermaid source much easier to read and debug.
  makeIdSanitizer =
    prefix: s:
    let
      sanitized = sanitizeChars s;
      needsPrefix =
        builtins.elem sanitized mermaidReservedIds
        || builtins.match "[0-9].*" sanitized != null
        || sanitized == "";
    in
    if needsPrefix then "${prefix}_${sanitized}" else sanitized;

  # Canonical entity kind label. If withCtxKeys is false the `{ a, b }` suffix
  # is dropped — ishikawa uses this because its parser doesn't tolerate braces.
  entityLabel =
    {
      withCtxKeys ? true,
    }:
    stage:
    stage.name
    + (
      if withCtxKeys && stage.ctxKeys != [ ] then
        " { ${lib.concatStringsSep ", " stage.ctxKeys} }"
      else
        ""
    );

  # Shared style-classifier predicates. Node `style` is a coarse bucket
  # set in `graph.nix::nodeStyle` and consumed by every renderer and
  # every style-aware filter. Defining the buckets in one place keeps
  # filters consistent when the vocabulary grows.
  # Rendering style string — for renderers only.
  styleOf = n: n.style or "default";

  # Structural predicates — for filters. Read the structural booleans
  # set in graph.nix::mkNode rather than the rendering `style` string.
  isTombstone = n: (n.isExcluded or false) || (n.isReplaced or false);
  isAdapter = n: (styleOf n) == "adapter";

  # Keep only nodes whose style is in `styles` (a list of strings).
  # Thin wrapper over filterByNodes. Collapses `adaptersOnly`,
  # tombstone-only, etc. into single-line calls.
  filterByStyle =
    styles: graph:
    let
      styleSet = lib.listToAttrs (
        builtins.map (s: {
          name = s;
          value = true;
        }) styles
      );
    in
    filterByNodes (n: styleSet ? ${styleOf n}) graph;

  # Build {from-id -> [to-ids]} and {to-id -> [from-ids]} adjacency tables
  # from a list of edges. Consumers do O(1) lookups instead of linear scans
  # per traversal step.
  adjacency =
    edges:
    let
      outOf = lib.foldl' (acc: e: acc // { ${e.from} = (acc.${e.from} or [ ]) ++ [ e.to ]; }) { } edges;
      inTo = lib.foldl' (acc: e: acc // { ${e.to} = (acc.${e.to} or [ ]) ++ [ e.from ]; }) { } edges;
    in
    {
      inherit outOf inTo;
    };

  # --- Subgraph primitives ---
  #
  # Shared helpers for filter/reshape functions in graph.nix and
  # filters.nix. Each one returns a graph record with nodes+edges
  # restricted to the specified subset, preserving everything else
  # (rootName, rootId, direction, entityKinds, entityEdges).

  # Build a `{ id = true; }` attrset from a list of nodes.
  idSetOfNodes =
    nodes:
    lib.listToAttrs (
      map (n: {
        name = n.id;
        value = true;
      }) nodes
    );

  # Restrict a graph to nodes whose id is in `keptIds` (a `{ id = true; }`
  # attrset). Edges are pruned to ones where BOTH endpoints survive.
  subgraphByIds =
    keptIds: graph:
    graph
    // {
      nodes = builtins.filter (n: keptIds ? ${n.id}) graph.nodes;
      edges = builtins.filter (e: keptIds ? ${e.from} && keptIds ? ${e.to}) graph.edges;
    };

  # Filter a graph by a node predicate. Edges are pruned to ones where
  # both endpoints pass. Used by most "keep only X" style filters.
  filterByNodes = pred: graph: subgraphByIds (idSetOfNodes (builtins.filter pred graph.nodes)) graph;

  # 1-hop neighborhood around the nodes matching `pred`: the matches
  # themselves plus every node connected to one of them by an incoming
  # OR outgoing edge. Edges are the FULL induced subgraph on that id
  # set — meaning edges between two non-seed neighbors are kept too,
  # since they show structural context around the seed. Used by
  # neighborhoodOf / adaptersOnly / parametricOnly.
  neighborhoodByNodes =
    pred: graph:
    let
      seedIds = idSetOfNodes (builtins.filter pred graph.nodes);
      expanded = lib.foldl' (
        acc: e:
        if seedIds ? ${e.from} then
          acc // { ${e.to} = true; }
        else if seedIds ? ${e.to} then
          acc // { ${e.from} = true; }
        else
          acc
      ) seedIds graph.edges;
    in
    subgraphByIds expanded graph;

  # Transitive ancestor closure of nodes matching `pred`: start with
  # the matches and walk backward through `in-edge` adjacency until
  # no new ancestors appear. Used by classSlice where we want to
  # preserve the inclusion hierarchy above each seed.
  ancestorClosureBy =
    pred: graph:
    let
      adj = adjacency graph.edges;
      parentsOf = id: adj.inTo.${id} or [ ];
      seeds = builtins.filter pred graph.nodes;
      expand =
        id: visited:
        if visited ? ${id} then
          visited
        else
          let
            v = visited // {
              ${id} = true;
            };
          in
          lib.foldl' (acc: p: expand p acc) v (parentsOf id);
      keptIds = lib.foldl' (acc: n: expand n.id acc) { } seeds;
    in
    subgraphByIds keptIds graph;

  # Detect cross-entity-kind bridges in a graph.
  # Returns list of { aspect, src, dst, kind, node } records.
  # Two detection methods:
  #   1. Provide wrappers: parse `<aspect>/<kind>/(self|cross)-provide(<dst>):<aspect>` labels
  #   2. Entity bridges: `to-<kind>` provider sub-aspect naming convention
  detectBridges =
    graph:
    let
      inherit (graph) nodes entityKinds;
      kindNames = map (s: s.name) entityKinds;

      # Parse wrapper labels for cross-entity provide hints.
      # Patterns we care about (matched against `fullLabel`, not `label`,
      # so aspect names stay unambiguous even if the short form was
      # chosen for display):
      #   <aspect>/<src>/self-provide(<dst>):<aspect>
      #   <aspect>/<src>/cross-provide(<dst>):<aspect>
      # Returns null for non-matching labels.
      parseProvide =
        label:
        let
          m = builtins.match "(.+)/([a-z-]+)/(self-provide|cross-provide)\\(([^)]+)\\):(.+)" label;
        in
        if m == null then
          null
        else
          {
            aspect = builtins.elemAt m 0;
            src = builtins.elemAt m 1;
            kind = builtins.elemAt m 2;
            dst = builtins.elemAt m 3;
          };

      # Wrapper nodes annotated with parsed provide info.
      provideWrappers = builtins.filter (p: p != null) (
        map (
          n:
          let
            p = parseProvide (n.fullLabel or n.label);
          in
          if p == null then null else p // { node = n; }
        ) nodes
      );

      # `alice/to-hosts` and similar provider-sub-aspects bridge entity
      # kinds implicitly — the sub-aspect lives in one kind but its content
      # goes elsewhere via provides.* naming conventions. Detect the
      # common `to-<kind>` / `to-hosts` sub-aspects as entity bridges.
      entityBridges = lib.concatMap (
        n:
        let
          pp = n.providerPath or [ ];
          tail =
            if pp == [ ] then
              null
            else
              let
                parts = lib.splitString "/" n.label;
              in
              if parts == [ ] then null else lib.last parts;
          dstKind =
            if tail == null then
              null
            else if tail == "to-hosts" then
              "host"
            else if lib.hasPrefix "to-" tail && builtins.elem (lib.removePrefix "to-" tail) kindNames then
              lib.removePrefix "to-" tail
            else
              null;
        in
        if dstKind != null && (n.entityKind or null) != null then
          [
            {
              src = n.entityKind;
              dst = dstKind;
              aspect = n.label;
              kind = "bridge";
              node = n;
            }
          ]
        else
          [ ]
      ) nodes;
    in
    provideWrappers ++ entityBridges;

  # Null-coalescing accessor: treats both missing and explicit-null as
  # "use the default". Plain `attr or default` only falls through on
  # missing — explicit null still returns null.
  nullOr = default: value: if value == null then default else value;

in
{
  inherit
    dedupBy
    fmtArgs
    meaningful
    nullOr
    isWrapper
    isUserAspect
    makeIdSanitizer
    sanitizeChars
    entityLabel
    styleOf
    isTombstone
    isAdapter
    filterByStyle
    adjacency
    idSetOfNodes
    subgraphByIds
    filterByNodes
    neighborhoodByNodes
    ancestorClosureBy
    detectBridges
    ;
}
