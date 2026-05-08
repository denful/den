# Plain-text / markdown renderers for data visualization.
#
# Produces structured markdown summaries from graph IR and fleet
# capture data. Useful for CLI inspection, documentation embedding,
# and LLM-friendly configuration review.
#
# All functions return plain strings (not derivations).
{ lib }:
let
  # --- Table helpers ---

  # Render a markdown table from headers and rows.
  # headers: [ "Col1" "Col2" ]
  # rows: [ [ "val1" "val2" ] [ "val3" "val4" ] ]
  mkTable =
    headers: rows:
    let
      separator = map (h: lib.concatMapStrings (_: "-") (lib.stringToCharacters h) + "--") headers;
      fmtRow = cols: "| ${lib.concatStringsSep " | " cols} |";
    in
    lib.concatStringsSep "\n" (
      [
        (fmtRow headers)
        (fmtRow separator)
      ]
      ++ map fmtRow rows
    );

  # --- Fleet summary ---

  fleetSummary =
    fleetCapture:
    let
      inherit (fleetCapture)
        entries
        scopeParent
        scopeContexts
        scopeEntityKind
        scopedPipeEffects
        scopedClassImports
        ctxTrace
        ;

      allScopes = builtins.attrNames scopeEntityKind;
      hostScopes = builtins.filter (s: scopeEntityKind.${s} == "host") allScopes;
      envScopes = builtins.filter (s: scopeEntityKind.${s} == "environment") allScopes;
      userScopes = builtins.filter (s: scopeEntityKind.${s} == "user") allScopes;

      extractName =
        kind: scopeId:
        let
          parts = lib.splitString "," scopeId;
          match = lib.findFirst (p: lib.hasPrefix "${kind}=" p) null parts;
        in
        if match != null then lib.removePrefix "${kind}=" match else scopeId;

      hostsInEnv = envScope: builtins.filter (h: (scopeParent.${h} or null) == envScope) hostScopes;

      usersInHost = hostScope: builtins.filter (u: (scopeParent.${u} or null) == hostScope) userScopes;

      # Policy entries.
      policyEntries = builtins.filter (e: e.isPolicyDispatch or false) entries;
      policyNames = lib.unique (map (e: e.name) policyEntries);

      # Pipe data.
      classKeys = [
        "nixos"
        "homeManager"
        "user"
        "darwin"
      ];
      isPipeKey = k: !builtins.elem k classKeys;

      pipesByHost = map (
        hScope:
        let
          hName = extractName "host" hScope;
          ci = scopedClassImports.${hScope} or { };
          pipes = builtins.filter isPipeKey (builtins.attrNames ci);
          effects = scopedPipeEffects.${hScope} or [ ];
          collectPipes = lib.unique (
            builtins.filter (p: p != null) (
              map (e: e.value.pipeName or e.pipeName or null) (
                builtins.filter (
                  e: builtins.any (s: (s.__pipeStage or null) == "collect") (e.value.stages or e.stages or [ ])
                ) effects
              )
            )
          );
        in
        {
          name = hName;
          produces = pipes;
          collects = collectPipes;
        }
      ) hostScopes;

      allPipeNames = lib.unique (lib.concatMap (h: h.produces ++ h.collects) pipesByHost);

      # Scope chain from ctxTrace.
      kindChain = lib.concatStringsSep " → " (lib.reverseList (map (e: e.key) ctxTrace));

      # Environment table.
      envRows = map (
        envScope:
        let
          eName = extractName "environment" envScope;
          hosts = hostsInEnv envScope;
          hostNames = map (extractName "host") hosts;
          userCount = builtins.length (lib.concatMap usersInHost hosts);
        in
        [
          eName
          (lib.concatStringsSep ", " hostNames)
          (toString (builtins.length hosts))
          (toString userCount)
        ]
      ) envScopes;

      # Pipe table — grouped by collection boundary (the parent scope of
      # collecting hosts). pipe.collect finds siblings = same parent.
      # The boundary kind is whatever entity kind the parent scope has.
      hostParentScopes = lib.unique (map (hScope: scopeParent.${hScope} or null) hostScopes);

      pipeRows = lib.concatMap (
        pipeName:
        lib.concatMap (
          parentScope:
          let
            parentKind = if parentScope != null then scopeEntityKind.${parentScope} or null else null;
            parentName =
              if parentScope != null && parentKind != null then extractName parentKind parentScope else "global";
            boundary = if parentKind != null then "${parentKind}: ${parentName}" else "global";
            siblingHosts = builtins.filter (h: (scopeParent.${h} or null) == parentScope) hostScopes;
            siblingNames = map (extractName "host") siblingHosts;
            producers = builtins.filter (
              h: builtins.elem pipeName h.produces && builtins.elem h.name siblingNames
            ) pipesByHost;
            collectors = builtins.filter (
              h: builtins.elem pipeName h.collects && builtins.elem h.name siblingNames
            ) pipesByHost;
            pureConsumers = builtins.filter (h: !builtins.elem pipeName h.produces) collectors;
            effectiveConsumers = if pureConsumers != [ ] then pureConsumers else collectors;
          in
          lib.optional (producers != [ ] || effectiveConsumers != [ ]) [
            pipeName
            boundary
            (lib.concatStringsSep ", " (map (h: h.name) producers))
            (lib.concatStringsSep ", " (map (h: h.name) effectiveConsumers))
          ]
        ) hostParentScopes
      ) allPipeNames;

      # Policy table.
      policyRows = map (
        name:
        let
          entry = lib.findFirst (e: e.name == name) null policyEntries;
          from = if entry != null then entry.from or "—" else "—";
        in
        [
          name
          from
        ]
      ) policyNames;

      # Aspect counts per host.
      aspectEntries = builtins.filter (
        e:
        !(e.isPolicyDispatch or false)
        && (e.hasClass or false)
        && (e.provider or [ ]) == [ ]
        && e.name != "host"
        && e.name != "user"
        && e.name != "default"
        && !(lib.hasPrefix "<" (e.name or ""))
      ) entries;

      aspectsByHost = lib.foldl' (
        acc: e:
        let
          inst = e.entityInstance or "";
          parts = lib.splitString ":" inst;
          kind = builtins.head parts;
          name = if builtins.length parts > 1 then lib.concatStringsSep ":" (lib.tail parts) else "";
        in
        if kind == "host" && name != "" then
          acc // { ${name} = lib.unique ((acc.${name} or [ ]) ++ [ e.name ]); }
        else
          acc
      ) { } aspectEntries;

      hostAspectRows = map (
        hScope:
        let
          hName = extractName "host" hScope;
          aspects = aspectsByHost.${hName} or [ ];
        in
        [
          hName
          (toString (builtins.length aspects))
          (lib.concatStringsSep ", " (lib.take 8 (lib.sort (a: b: a < b) aspects)))
        ]
      ) hostScopes;
    in
    lib.concatStringsSep "\n" [
      "# Fleet Summary"
      ""
      "## Topology"
      ""
      "- **${toString (builtins.length envScopes)}** environments, **${toString (builtins.length hostScopes)}** hosts, **${toString (builtins.length userScopes)}** users"
      "- Scope chain: ${kindChain}"
      "- Trace entries: ${toString (builtins.length entries)}"
      ""
      "## Environments"
      ""
      (mkTable [
        "Environment"
        "Hosts"
        "Host Count"
        "Users"
      ] envRows)
      ""
      "## Aspects by Host"
      ""
      (mkTable [
        "Host"
        "Aspect Count"
        "Aspects"
      ] hostAspectRows)
      ""
      (
        if allPipeNames != [ ] then
          lib.concatStringsSep "\n" [
            "## Pipes"
            ""
            (mkTable [
              "Pipe"
              "Scope Boundary"
              "Producers"
              "Collectors"
            ] pipeRows)
          ]
        else
          ""
      )
      ""
      "## Policies"
      ""
      (mkTable [
        "Policy"
        "Fires at"
      ] policyRows)
    ];

  # --- Per-host summary ---

  hostSummary =
    {
      graph,
      host ? null,
      fleetCapture ? null,
    }:
    let
      inherit (graph) nodes edges;

      hostName = graph.rootName;

      # Meaningful user aspects.
      userAspects = builtins.filter (
        n: (n.hasClass or false) && !(n.isPolicyDispatch or false) && !(lib.hasPrefix "<" n.label)
      ) nodes;

      # Group by entity instance.
      instanceGroups = lib.foldl' (
        acc: n:
        let
          inst = n.entityInstance or "unscoped";
        in
        acc // { ${inst} = (acc.${inst} or [ ]) ++ [ n ]; }
      ) { } userAspects;

      # Policies.
      policyNodes = builtins.filter (n: n.isPolicyDispatch or false) nodes;

      # Providers.
      providerNodes = builtins.filter (n: n.isProvider or false) nodes;

      # Classes present.
      allClasses = lib.unique (lib.concatMap (n: n.classes or [ ]) userAspects);

      # Aspect table.
      aspectRows = map (n: [
        n.label
        (lib.concatStringsSep ", " (n.classes or [ ]))
        (
          if n.isParametric or false then "yes (${lib.concatStringsSep ", " (n.fnArgNames or [ ])})" else "no"
        )
        (n.entityInstance or "—")
      ]) (lib.sort (a: b: a.label < b.label) userAspects);

      # Class breakdown.
      classBreakdowns = map (
        className:
        let
          classAspects = builtins.filter (n: builtins.elem className (n.classes or [ ])) userAspects;
          names = lib.sort (a: b: a < b) (map (n: n.label) classAspects);
        in
        "### ${className} (${toString (builtins.length names)})\n\n${
          lib.concatMapStringsSep "\n" (n: "- ${n}") names
        }"
      ) allClasses;

      # Provider breakdown.
      providerRows = map (n: [
        n.label
        (lib.concatStringsSep ", " (n.classes or [ ]))
        (lib.concatStringsSep "/" (n.providerPath or [ ]))
      ]) (lib.sort (a: b: a.label < b.label) providerNodes);

      # Pipe data from fleet capture if available.
      pipeSection =
        if fleetCapture == null then
          ""
        else
          let
            inherit (fleetCapture)
              scopedPipeEffects
              scopedClassImports
              scopeParent
              scopeEntityKind
              ;
            # Find the host scope matching this host name.
            hostScopes = builtins.filter (
              s:
              (scopeEntityKind.${s} or null) == "host"
              && lib.hasSuffix "host=${hostName}" (lib.last (lib.splitString "," s))
            ) (builtins.attrNames scopeEntityKind);
            hScope = if hostScopes != [ ] then builtins.head hostScopes else null;
            ci = if hScope != null then scopedClassImports.${hScope} or { } else { };
            classKeySet = [
              "nixos"
              "homeManager"
              "user"
              "darwin"
            ];
            producedPipes = builtins.filter (k: !builtins.elem k classKeySet) (builtins.attrNames ci);
            effects = if hScope != null then scopedPipeEffects.${hScope} or [ ] else [ ];
            collectPipes = lib.unique (
              builtins.filter (p: p != null) (
                map (e: e.value.pipeName or e.pipeName or null) (
                  builtins.filter (
                    e: builtins.any (s: (s.__pipeStage or null) == "collect") (e.value.stages or e.stages or [ ])
                  ) effects
                )
              )
            );
            # Find siblings that produce pipes this host collects.
            siblings =
              if hScope != null then
                let
                  parent = scopeParent.${hScope} or null;
                in
                builtins.filter (
                  s: s != hScope && (scopeParent.${s} or null) == parent && (scopeEntityKind.${s} or null) == "host"
                ) (builtins.attrNames scopeParent)
              else
                [ ];
            siblingNames = map (
              s:
              let
                parts = lib.splitString "," s;
                hp = lib.findFirst (p: lib.hasPrefix "host=" p) null parts;
              in
              if hp != null then lib.removePrefix "host=" hp else s
            ) siblings;
          in
          lib.concatStringsSep "\n" (
            [
              ""
              "## Pipe Data"
              ""
              "**Produces:** ${if producedPipes != [ ] then lib.concatStringsSep ", " producedPipes else "none"}"
              "**Collects:** ${if collectPipes != [ ] then lib.concatStringsSep ", " collectPipes else "none"}"
            ]
            ++ lib.optional (siblingNames != [ ]) "**Siblings:** ${lib.concatStringsSep ", " siblingNames}"
          );
    in
    lib.concatStringsSep "\n" (
      [
        "# Host: ${hostName}"
        ""
        "## Overview"
        ""
        "- **${toString (builtins.length userAspects)}** aspects across **${toString (builtins.length allClasses)}** classes (${lib.concatStringsSep ", " allClasses})"
        "- **${toString (builtins.length providerNodes)}** provider sub-aspects"
        "- **${toString (builtins.length policyNodes)}** policies fired"
        "- **${toString (builtins.length (builtins.attrNames instanceGroups))}** entity instances"
        ""
        "## Aspects"
        ""
        (mkTable [
          "Aspect"
          "Classes"
          "Parametric"
          "Instance"
        ] aspectRows)
        ""
        "## Classes"
        ""
      ]
      ++ lib.intersperse "\n" classBreakdowns
      ++ [
        ""
        ""
        "## Providers"
        ""
        (mkTable [
          "Provider Aspect"
          "Classes"
          "Provider Path"
        ] providerRows)
        ""
        "## Policies"
        ""
        (lib.concatMapStringsSep "\n" (p: "- **${p.policyName or p.label}** (from: ${p.from or "—"})") (
          lib.sort (a: b: (a.policyName or a.label) < (b.policyName or b.label)) policyNodes
        ))
        pipeSection
      ]
    );

in
{
  inherit
    fleetSummary
    hostSummary
    mkTable
    ;
}
