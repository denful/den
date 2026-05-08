# Sequence diagram renderer.
#
# Maps the context resolution pipeline to a sequenceDiagram:
#   - participants    = context stages (host, default, hm-host, hm-user, user)
#   - messages        = entityEdges (normal or cross-provide)
#   - notes           = aspect labels grouped per stage, truncated
#
# The pipeline is naturally sequential, so this view reveals causal flow
# (who-resolves-before-whom) rather than structural containment.
{
  lib,
  themes,
  util,
  renderUtil,
}:
let
  inherit (util) meaningful isUserAspect makeIdSanitizer;
  inherit (renderUtil) renderMermaid;

  # Stable alias for mermaid sequenceDiagram participants.
  aliasOf = makeIdSanitizer "p";

  entityLabel = util.entityLabel { };

  # Topologically order entity kinds: roots (no incoming entityEdge) first,
  # then rest in insertion order. We only need approximate order for readability.
  orderEntityKinds =
    entityKinds: entityEdges:
    let
      targets = lib.listToAttrs (
        map (e: {
          name = e.to;
          value = true;
        }) entityEdges
      );
      isRoot = s: !(targets ? ${s.id});
    in
    builtins.filter isRoot entityKinds ++ builtins.filter (s: !(isRoot s)) entityKinds;

  nodeLabel =
    n:
    let
      base = n.label or n.name or "<anon>";
      args = n.fnArgNames or [ ];
    in
    if args != [ ] then "${base}(${util.fmtArgs args})" else base;

  noteWrapAt = 4;

  # Word-wrap a label list into <br/>-joined chunks of noteWrapAt.
  wrapLabels =
    labels:
    let
      len = builtins.length labels;
      numChunks = if len == 0 then 0 else (len + noteWrapAt - 1) / noteWrapAt;
    in
    lib.concatStringsSep "<br/>" (
      builtins.filter (c: c != "") (
        lib.genList (
          i: lib.concatStringsSep ", " (lib.take noteWrapAt (lib.drop (i * noteWrapAt) labels))
        ) numChunks
      )
    );

  mkEntityById =
    entityKinds:
    lib.listToAttrs (
      map (s: {
        name = s.id;
        value = s;
      }) entityKinds
    );

  policyNodesOf = nodes: builtins.filter (n: n.isPolicyDispatch or false) nodes;

  toSequenceMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    graph:
    let
      inherit (graph)
        rootName
        nodes
        entityKinds
        entityEdges
        ;
      ordered = orderEntityKinds entityKinds entityEdges;

      participantDecl = ek: "    participant ${aliasOf ek.name} as ${entityLabel ek}";

      entityById = mkEntityById entityKinds;
      messageDecl =
        edge:
        let
          fromEntity = entityById.${edge.from} or null;
          toEntity = entityById.${edge.to} or null;
          fromAlias = if fromEntity != null then aliasOf fromEntity.name else edge.from;
          toAlias = if toEntity != null then aliasOf toEntity.name else edge.to;
          label = if edge.label != null then edge.label else "resolve";
          arrow = if (edge.style or "normal") == "provide" then "-->>" else "->>";
        in
        "    ${fromAlias} ${arrow} ${toAlias}: ${label}";

      # Drop self-reference entity kind transitions (edges where source and
      # target collapse to the same participant). They render as a
      # self-arrow in sequenceDiagram — confusing and conveys nothing
      # the entity note doesn't already say.
      nonSelfEntityEdges = builtins.filter (e: e.from != e.to) entityEdges;

      # Policy dispatch messages with context annotation.
      policyNodes = policyNodesOf nodes;
      policyMessages = lib.concatMap (
        pn:
        let
          fromKind = pn.from or null;
          toKind = pn.to or null;
          fromAlias = if fromKind != null then aliasOf fromKind else null;
          toAlias = if toKind != null then aliasOf toKind else null;
          policyName = pn.policyName or pn.label;
        in
        lib.optional (
          fromAlias != null && toAlias != null && fromAlias != toAlias
        ) "    ${fromAlias} -->> ${toAlias}: ${policyName}"
      ) policyNodes;

      # Per-entity-kind aspect blocks: show parametric aspects with their args
      # and non-parametric aspects grouped separately.
      entityBlock =
        ek:
        let
          alias = aliasOf ek.name;
          ekNodes = builtins.filter (
            n: n.entityKind == ek.name && meaningful n.label && !(n.isPolicyDispatch or false)
          ) nodes;
          parametric = builtins.filter (n: (n.fnArgNames or [ ]) != [ ]) ekNodes;
          static = builtins.filter (n: (n.fnArgNames or [ ]) == [ ]) ekNodes;
          parametricLines = map (n: "    ${alias} ->> ${alias}: ${nodeLabel n}") parametric;
          staticLabels = map (n: n.label) static;
          staticNote = wrapLabels staticLabels;
        in
        (
          if parametricLines != [ ] then
            [ "    activate ${alias}" ] ++ parametricLines ++ [ "    deactivate ${alias}" ]
          else
            [ ]
        )
        ++ lib.optional (staticNote != "") "    Note over ${alias}: ${staticNote}";
    in
    if entityKinds == [ ] then
      renderMermaid
        {
          inherit theme mermaidConfig;
          diagramKind = "sequenceDiagram";
        }
        [
          "    participant root as ${rootName}"
          "    Note over root: no entity kinds captured"
        ]
    else
      renderMermaid
        {
          inherit theme mermaidConfig;
          diagramKind = "sequenceDiagram";
        }
        (
          map participantDecl ordered
          ++ [ "" ]
          ++ map messageDecl nonSelfEntityEdges
          ++ (if policyMessages != [ ] then [ "" ] ++ policyMessages else [ ])
          ++ lib.concatMap (s: [ "" ] ++ entityBlock s) ordered
        );

  # Expanded variant: same entity kind participants and inter-kind
  # transitions as the basic sequence view but with an UNTRUNCATED
  # per-kind aspect list (rendered as a sequenceDiagram `Note over`)
  # plus explicit cross-kind provide arrows for wrapper nodes.
  #
  # Aspects are NOT emitted as per-aspect self-arrows — those render
  # as visible self-loops and bury the actual inter-kind flow. A note
  # listing every aspect conveys the same detail without the loops.
  #
  # Cross-kind projection hints: wrapper nodes matching
  # `<aspect>/<src>/(self-provide|cross-provide)(<dst>):<aspect>` become
  # src→dst arrows (same-kind self-provides filtered out). Provider
  # sub-aspects named `to-hosts` / `to-<kind>` bridge from the aspect's
  # own kind to the target kind.
  toSequenceMermaidExpandedWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    graph:
    let
      inherit (graph)
        rootName
        nodes
        entityKinds
        entityEdges
        ;

      ordered = orderEntityKinds entityKinds entityEdges;
      entityById = mkEntityById entityKinds;
      aspectsByEntityKind =
        ek:
        lib.sort (a: b: a.label < b.label) (
          builtins.filter (n: n.entityKind == ek.name && isUserAspect graph n) nodes
        );

      allBridges = util.detectBridges graph;

      participantDecl = ek: "    participant ${aliasOf ek.name} as ${entityLabel ek}";

      # Per-entity-kind block:
      #   1. Header note marking the entity kind
      #   2. Content note listing every user aspect in the kind (no
      #      truncation — that's the "expanded" bit)
      #   3. Non-self cross-kind bridges originating in this kind
      #   4. Non-self outgoing kind transitions from this kind
      #
      # Self-reference arrows (src == dst) are filtered at every step.
      # Policy nodes grouped by source entity kind for dispatch arrows.
      policyNodesByEntityKind =
        ek: builtins.filter (n: (n.isPolicyDispatch or false) && (n.from or null) == ek.name) nodes;

      entityBlock =
        ek:
        let
          alias = aliasOf ek.name;
          aspects = aspectsByEntityKind ek;
          outgoing = builtins.filter (e: e.from == ek.id && e.to != ek.id) entityEdges;
          bridgesFromHere = builtins.filter (b: b.src == ek.name && b.dst != ek.name) allBridges;
          ekPolicies = policyNodesByEntityKind ek;

          # Split aspects into parametric (with ctx args) and static.
          parametric = builtins.filter (n: (n.fnArgNames or [ ]) != [ ]) aspects;
          static = builtins.filter (n: (n.fnArgNames or [ ]) == [ ]) aspects;

          # Parametric aspects as self-arrows with arg annotation.
          parametricLines =
            if parametric == [ ] then
              [ ]
            else
              [ "    activate ${alias}" ]
              ++ map (n: "    ${alias} ->> ${alias}: ${nodeLabel n}") parametric
              ++ [ "    deactivate ${alias}" ];

          # Static aspects as word-wrapped note.
          staticLabels = map (n: n.label) static;
          staticChunks = lib.genList (
            i: lib.concatStringsSep ", " (lib.take noteWrapAt (lib.drop (i * noteWrapAt) staticLabels))
          ) (if staticLabels == [ ] then 0 else (builtins.length staticLabels + noteWrapAt - 1) / noteWrapAt);
          staticNote = lib.concatStringsSep "<br/>" (builtins.filter (c: c != "") staticChunks);

          # Policy dispatch arrows from this entity kind.
          policyLines = lib.concatMap (
            pn:
            let
              toKind = pn.to or null;
              toAlias = if toKind != null then aliasOf toKind else null;
              policyName = pn.policyName or pn.label;
            in
            lib.optional (toAlias != null && toAlias != alias) "    ${alias} -->> ${toAlias}: ${policyName}"
          ) ekPolicies;

          bridgeLine =
            b:
            let
              dstAlias = aliasOf b.dst;
              arrow = if b.kind == "cross-provide" || b.kind == "bridge" then "-->>" else "->>";
              label = if b.kind == "bridge" then "forward: ${b.aspect}" else "${b.kind}: ${b.aspect}";
            in
            "    ${alias} ${arrow} ${dstAlias}: ${label}";

          transitionLine =
            edge:
            let
              toEntity = entityById.${edge.to} or null;
              toAlias = if toEntity != null then aliasOf toEntity.name else edge.to;
              label = if edge.label != null then edge.label else "resolve";
              arrow = if (edge.style or "normal") == "provide" then "-->>" else "->>";
            in
            "    ${alias} ${arrow} ${toAlias}: ${label}";
        in
        [
          ""
          "    Note over ${alias}: ── ${entityLabel ek}"
        ]
        ++ parametricLines
        ++ lib.optional (staticNote != "") "    Note over ${alias}: ${staticNote}"
        ++ (if bridgesFromHere != [ ] then [ "" ] else [ ])
        ++ map bridgeLine bridgesFromHere
        ++ (if policyLines != [ ] then [ "" ] else [ ])
        ++ policyLines
        ++ (if outgoing != [ ] then [ "" ] else [ ])
        ++ map transitionLine outgoing;
    in
    if entityKinds == [ ] then
      renderMermaid
        {
          inherit theme mermaidConfig;
          diagramKind = "sequenceDiagram";
        }
        [
          "    participant root as ${rootName}"
          "    Note over root: no entity kinds captured"
        ]
    else
      renderMermaid {
        inherit theme mermaidConfig;
        diagramKind = "sequenceDiagram";
      } (map participantDecl ordered ++ lib.concatMap entityBlock ordered);

  toSequenceMermaid = toSequenceMermaidWith { };
  toSequenceMermaidExpanded = toSequenceMermaidExpandedWith { };

  # Entity kind topology: focused flowchart showing only pipeline entity
  # kinds and their transition edges. Answers "what is the resolution order?"
  # without any aspect-level detail.
  toScopeEdgesMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    graph:
    let
      inherit (graph) entityKinds entityEdges rootName;
      ordered = orderEntityKinds entityKinds entityEdges;
      entityById = mkEntityById entityKinds;
      nodeDecl = ek: "    ${aliasOf ek.name}([${entityLabel ek}])";
      edgeDecl =
        edge:
        let
          fromEntity = entityById.${edge.from} or null;
          toEntity = entityById.${edge.to} or null;
        in
        if fromEntity == null || toEntity == null then
          null
        else
          let
            arrow = if (edge.style or "normal") == "provide" then "-.->" else "-->";
            lbl = if edge.label != null then "|${edge.label}|" else "";
          in
          "    ${aliasOf fromEntity.name} ${arrow}${lbl} ${aliasOf toEntity.name}";
      edgeLines = builtins.filter (l: l != null) (map edgeDecl entityEdges);
    in
    if entityKinds == [ ] then
      renderMermaid {
        inherit theme mermaidConfig;
        diagramKind = "graph LR";
      } [ "    root([${rootName}])" ]
    else
      renderMermaid {
        inherit theme mermaidConfig;
        diagramKind = "graph LR";
      } (map nodeDecl ordered ++ (if edgeLines != [ ] then [ "" ] ++ edgeLines else [ ]));

  toScopeEdgesMermaid = toScopeEdgesMermaidWith { };

  # Policy-centric sequence: policies ARE the participants.
  # Shows each policy as an actor, what context it receives,
  # what aspects it triggers, and how policies chain.
  toPolicySequenceMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    graph:
    let
      inherit (graph)
        rootName
        nodes
        entityKinds
        entityEdges
        ;

      orEmpty = v: if v == null then "" else v;
      policyNodes = lib.sort (
        a: b:
        let
          af = orEmpty (a.from or null);
          bf = orEmpty (b.from or null);
          at = orEmpty (a.to or null);
          bt = orEmpty (b.to or null);
        in
        af < bf || (af == bf && at < bt)
      ) (builtins.filter (n: n.isPolicyDispatch or false) nodes);

      # Aspects grouped by target entity kind.
      aspectsByEntityKind =
        kindName:
        builtins.filter (
          n: n.entityKind == kindName && meaningful n.label && !(n.isPolicyDispatch or false)
        ) nodes;

      # Root entity participant.
      rootParticipant = "    participant root as ${rootName}";

      # Each policy becomes a participant.
      policyParticipants = map (
        pn: "    participant ${aliasOf (pn.policyName or pn.label)} as ${pn.policyName or pn.label}"
      ) policyNodes;

      childrenOf = (util.adjacency (graph.edges or [ ])).outOf;

      nodeById = lib.listToAttrs (
        map (n: {
          name = n.id;
          value = n;
        }) nodes
      );

      # For each policy: root dispatches to it, it activates and shows
      # the aspects it triggers grouped by entity.
      policyBlock =
        pn:
        let
          pAlias = aliasOf (pn.policyName or pn.label);
          toKind = pn.to or null;

          targetAspects = if toKind != null then aspectsByEntityKind toKind else [ ];

          # Top-level entities in this kind (parametric aspects with the
          # kind's context args — alice, bob, deploy, etc.)
          topEntities = builtins.filter (
            n:
            (n.fnArgNames or [ ]) != [ ]
            && !(lib.hasPrefix "provides/" n.label)
            && !(lib.hasPrefix "${toKind}/" n.label)
          ) targetAspects;

          # Group aspects by parent entity using edge relationships.
          entityBlock =
            entity:
            let
              childIds = childrenOf.${entity.id} or [ ];
              children = builtins.filter (n: builtins.elem n.id childIds && n.id != entity.id) targetAspects;
              childLabels = map (n: nodeLabel n) children;
            in
            [ "    Note over ${pAlias}: ${nodeLabel entity}" ]
            ++ map (l: "    ${pAlias} ->> ${pAlias}: ${l}") childLabels;

          # Aspects not parented to any top entity (kind-level).
          topEntityIds = map (n: n.id) topEntities;
          allEntityChildIds = lib.concatMap (e: childrenOf.${e.id} or [ ]) topEntities;
          topEntityIdSet = lib.genAttrs topEntityIds (_: true);
          allEntityChildIdSet = lib.genAttrs allEntityChildIds (_: true);
          orphans = builtins.filter (
            n: !(topEntityIdSet ? ${n.id}) && !(allEntityChildIdSet ? ${n.id})
          ) targetAspects;
          orphanLabels = map (n: nodeLabel n) orphans;
          orphanNote = wrapLabels orphanLabels;

          # Downstream policy chains.
          downstream = builtins.filter (p2: (p2.from or null) == toKind && p2 != pn) policyNodes;
          chainLines = map (
            p2: "    ${pAlias} -->> ${aliasOf (p2.policyName or p2.label)}: chains"
          ) downstream;
        in
        [
          ""
          "    root ->> ${pAlias}: dispatch"
          "    activate ${pAlias}"
        ]
        ++ lib.concatMap entityBlock topEntities
        ++ lib.optional (orphanNote != "") "    Note over ${pAlias}: ${orphanNote}"
        ++ chainLines
        ++ [ "    deactivate ${pAlias}" ];

      # Deduplicate: only show aspects for the first policy targeting
      # each stage.
      seenStages =
        builtins.foldl'
          (
            acc: pn:
            let
              to = orEmpty (pn.to or null);
              isFirst = !(acc.seen ? ${to});
              pAlias = aliasOf (pn.policyName or pn.label);
            in
            {
              seen = acc.seen // {
                ${to} = true;
              };
              blocks =
                acc.blocks
                ++ (
                  if isFirst then
                    policyBlock pn
                  else
                    [
                      ""
                      "    root ->> ${pAlias}: dispatch"
                    ]
                );
            }
          )
          {
            seen = { };
            blocks = [ ];
          }
          policyNodes;
    in
    if policyNodes == [ ] then
      renderMermaid
        {
          inherit theme mermaidConfig;
          diagramKind = "sequenceDiagram";
        }
        [
          "    participant root as ${rootName}"
          "    Note over root: no policies captured"
        ]
    else
      renderMermaid {
        inherit theme mermaidConfig;
        diagramKind = "sequenceDiagram";
      } ([ rootParticipant ] ++ policyParticipants ++ seenStages.blocks);

  toPolicySequenceMermaid = toPolicySequenceMermaidWith { };

in
{
  inherit
    toSequenceMermaid
    toSequenceMermaidWith
    toSequenceMermaidExpanded
    toSequenceMermaidExpandedWith
    toScopeEdgesMermaid
    toScopeEdgesMermaidWith
    toPolicySequenceMermaid
    toPolicySequenceMermaidWith
    ;
}
