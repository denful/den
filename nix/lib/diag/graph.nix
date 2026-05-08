# Graph IR construction.
#
# Transforms structuredTrace entries into a format-agnostic graph IR
# with nodes, edges, entity kinds, and entity kind transitions. The IR
# is consumed by the renderer modules (mermaid, dot, plantuml), which
# are responsible for anything visual — theme, colors, layout, diagram
# config are all render-time concerns and do not appear in the IR.
#
# Filter/reshape operations over the IR live in `filters.nix`.
{ lib, util }:
let
  inherit (util) dedupBy makeIdSanitizer sanitizeChars;

  # --- Helpers ---

  sanitize = makeIdSanitizer "n";

  # Default node record — used by `buildGraph.mkNode` as the starting
  # point AND by reshape filters (contextOnly, phantomStubEntries, etc.)
  # that need to synthesize nodes outside the normal entry-derived path.
  # Keeping defaults in one place means when the node schema grows a
  # new field, every synthesized node automatically inherits it.
  emptyNode = {
    id = "";
    label = "";
    fullLabel = "";
    # Canonical key matching `identity.pathKey (identity.aspectPath aspect)`.
    pathKey = "";
    shape = "rect";
    # Rendering style — drives color/border in renderers. Filters
    # should NOT use this for structural reasoning; use the structural
    # booleans below (`isExcluded`, `isReplaced`) instead.
    style = "default";
    entityKind = null;
    entityInstance = null;
    classes = [ ];
    class = "";
    perClass = { };
    fnArgNames = [ ];
    isParametric = false;
    isProvider = false;
    providerPath = [ ];
    hasClass = false;
    # Structural booleans for filters. Decoupled from `style` so
    # structural queries don't depend on the rendering vocabulary.
    isExcluded = false;
    isReplaced = false;
    isPolicyDispatch = false;
    policyName = null;
    from = null;
    to = null;
  };

  # Defensive default for synthetic trace entries (phantom providers, etc.).
  # Mirrors emptyNode: any field mkNode reads from entries has a safe fallback.
  stubEntry = name: {
    inherit name;
    class = "";
    parent = null;
    provider = [ ];
    excluded = false;
    excludedFrom = null;
    replacedBy = null;
    isProvider = false;
    handlers = [ ];
    hasAdapter = false;
    hasClass = false;
    isParametric = false;
    fnArgNames = [ ];
    entityKind = null;
    entityInstance = null;
  };

  # Full path: "provider/sub/.../name". Used for stable IDs and edge
  # key dedup — never changes meaning, always uniquely identifies an
  # entry within a trace.
  fullName =
    entry:
    if entry.provider != [ ] then
      lib.concatStringsSep "/" (entry.provider ++ [ entry.name ])
    else
      entry.name;

  # Compact display label: `<last-provider-segment>/<name>` for provider
  # sub-aspects, bare name for top-level aspects. This keeps visible
  # labels short enough that mermaid's HTML foreignObject text doesn't
  # wrap mid-path (which made `coolercontrol/class/enable` and
  # `coolercontrol/class/setup` look like duplicates in the rendered
  # SVG) while still disambiguating same-named leaves across providers
  # (`amdcpu/enable` vs `class/enable` vs `bat/enable`).
  displayName =
    entry:
    let
      p = entry.provider;
    in
    if p == [ ] then entry.name else "${lib.last p}/${entry.name}";

  # An entry's stable identifier is derived from its full path — not
  # its bare name — so `monitoring/enable` and `persist/enable` don't collide.
  entryId = entry: sanitize (fullName entry);

  # --- Graph IR builder ---

  buildGraph =
    {
      entries,
      rootName,
      ctxTrace ? [ ],
      direction ? "LR", # LR (left-right) or TD (top-down)
    }:
    let
      # Group raw entries by fullName so we can merge class info when
      # the same aspect appears in multiple class traces.
      #
      # `captureAll` iterates classes and invokes structuredTrace once
      # per class. Each invocation walks the entire aspect tree,
      # emitting an entry per aspect regardless of whether that aspect
      # has content for the current class. The adapter sets
      # `hasClass = classModule != []` — true when the aspect actually
      # defines attrs for this class, false when it's just traversed.
      #
      # To answer "which classes does this aspect contribute to?" we
      # merge ONLY the entries where `hasClass = true`. Otherwise every
      # aspect would look like it belongs to every class just because
      # the traversal visited it.
      # Pre-tag entries: assign root entity instance to entries with null
      # entityInstance so they merge correctly with same-scope entries
      # during dedup rather than creating duplicates.
      rootInstance =
        if ctxTrace != [ ] then
          let
            rootCtx = builtins.head ctxTrace;
          in
          "${rootCtx.entityKind}:${rootCtx.selfName}"
        else
          null;
      # Pre-tag: assign root entity instance to null-instance entries so
      # they merge with same-scope entries during dedup (no duplicates).
      preTagged = map (
        e:
        if (e.entityInstance or null) == null && rootInstance != null then
          e // { entityInstance = rootInstance; }
        else
          e
      ) entries;

      # Coerce null entityInstance to empty string for safe interpolation.
      instOf = e: if e.entityInstance or null == null then "" else e.entityInstance;

      # Scope-qualified key: dedup by (fullName, entityInstance) so the
      # same aspect in different entity scopes gets separate nodes. Within
      # one scope, class traces are still merged (nixos + homeManager
      # entries for the same aspect in the same instance combine).
      scopeKey =
        e:
        let
          inst = instOf e;
        in
        "${fullName e}|${inst}";

      groupedByName = lib.foldl' (
        acc: e:
        let
          k = scopeKey e;
        in
        acc // { ${k} = (acc.${k} or [ ]) ++ [ e ]; }
      ) { } preTagged;

      # Detect fullNames appearing in multiple entity instances — these
      # need scope-qualified IDs so nodes don't collide.
      instancesPerFullName = lib.foldl' (
        acc: e:
        let
          fn = fullName e;
          inst = instOf e;
        in
        acc // { ${fn} = lib.unique ((acc.${fn} or [ ]) ++ [ inst ]); }
      ) { } preTagged;
      isMultiInstance = fn: builtins.length (instancesPerFullName.${fn} or [ ]) > 1;

      # Scope-qualified entry ID: append entity instance suffix when the
      # same fullName exists in multiple scopes.
      seid =
        entry:
        let
          fn = fullName entry;
          inst = instOf entry;
        in
        if isMultiInstance fn && inst != "" then sanitize "${fn}@${inst}" else sanitize fn;

      # The classes this aspect actually contributes to (where
      # hasClass = true). Drives `node.class` and `node.classes`.
      classesByName = lib.mapAttrs (
        _: es:
        lib.unique (
          builtins.filter (c: c != null && c != "") (
            map (e: e.class or null) (builtins.filter (e: e.hasClass or false) es)
          )
        )
      ) groupedByName;

      # Per-class metadata for each aspect. Structural fields (parent,
      # provider, stage, isParametric) stay on the node top level since
      # they're class-independent. The fields here CAN differ per class
      # — hasClass is the discriminator, and excluded/replacedBy can
      # differ if `meta.handleWith` branches on class. Keyed by class name
      # so filters/renderers can ask "is this node active for nixos?".
      #
      # Merge semantics: when multiple entries exist for the same
      # (fullName, class) pair (because the trace visits the aspect
      # via multiple include paths), we OR the per-class flags — any
      # visit with hasClass=true or excluded=true is enough to mark
      # the class's metadata accordingly.
      mergePerClassField = a: b: {
        hasClass = a.hasClass || b.hasClass;
        excluded = a.excluded || b.excluded;
        replacedBy = if a.replacedBy != null then a.replacedBy else b.replacedBy;
        # Full aspectPath identity of the adapter owner that caused
        # the exclusion. Used by `decisionsView` for attribution-based
        # grouping. Takes the first non-null value — multiple entries
        # for the same (aspect, class) come from different traversal
        # paths but the adapter-owner identity is stable.
        excludedFrom = if a.excludedFrom != null then a.excludedFrom else b.excludedFrom;
      };

      perClassByName = lib.mapAttrs (
        _: es:
        lib.foldl' (
          acc: e:
          let
            c = e.class or "";
            newEntry = {
              hasClass = e.hasClass or false;
              excluded = e.excluded or false;
              replacedBy = e.replacedBy or null;
              excludedFrom = e.excludedFrom or null;
            };
          in
          if c == "" then
            acc
          else if acc ? ${c} then
            acc // { ${c} = mergePerClassField acc.${c} newEntry; }
          else
            acc // { ${c} = newEntry; }
        ) { } es
      ) groupedByName;

      nodes = dedupBy scopeKey preTagged;
      # Set of rendered node IDs for parent resolution.
      nodeIds = lib.listToAttrs (
        map (e: {
          name = seid e;
          value = true;
        }) nodes
      );
      # Set of excluded node IDs — edges FROM these are dropped.
      excludedIds = lib.listToAttrs (
        map (e: {
          name = seid e;
          value = true;
        }) (builtins.filter (e: e.excluded or false) preTagged)
      );

      # Resolve a parent reference to the correct scope-qualified ID.
      # When the parent appears in multiple scopes, prefer the same scope
      # as the child (same entityInstance).
      resolveParentId =
        parentName: childInst:
        let
          multi = isMultiInstance parentName;
          qualified = sanitize "${parentName}@${childInst}";
        in
        if !multi then
          sanitize parentName
        else if childInst != "" && nodeIds ? ${qualified} then
          qualified
        else
          sanitize parentName;

      edges = dedupBy (e: "${resolveParentId (e.parent or "") (instOf e)}->${seid e}") (
        builtins.filter (
          e: e.parent != null && !(excludedIds ? ${resolveParentId (e.parent or "") (instOf e)})
        ) preTagged
      );

      # Disambiguation: if two distinct entries would render to the same
      # short label (e.g. `coolercontrol/class/enable` and
      # `lact/class/enable` both shortening to `class/enable`), fall
      # back to the full path for the colliding ones. Unique short
      # labels stay short.
      shortLabelCounts = lib.foldl' (
        acc: e:
        let
          s = displayName e;
        in
        acc // { ${s} = (acc.${s} or 0) + 1; }
      ) { } nodes;
      displayLabel =
        entry:
        let
          s = displayName entry;
        in
        if (shortLabelCounts.${s} or 0) > 1 then fullName entry else s;

      # Provider-root lookup: map a top-level provider's bare name to
      # its entry. Used by `providerEdges` to resolve the source of a
      # `provider = [ "foo" ]` chain back to the entry definition of
      # `foo`. Only top-level entries (provider == []) are included,
      # so a sub-aspect like `bar/foo` can't accidentally shadow a
      # top-level `foo` aspect — root-level aspect names are unique
      # in the module system.
      topLevelEntryByName = lib.listToAttrs (
        map (e: {
          name = e.name;
          value = e;
        }) (builtins.filter (e: (e.provider or [ ]) == [ ]) preTagged)
      );

      # Entity kinds from __ctxTrace.
      ctxItems = builtins.filter (i: i.selfName != "<anon>") ctxTrace;
      entityKindNames = lib.unique (
        builtins.filter (s: s != null) (map (e: e.entityKind or null) preTagged)
      );

      # Node shape classification.
      nodeShape =
        entry:
        if entry.isParametric or false then
          "hexagon"
        else if entry.isProvider or false then
          "trapezoid"
        else
          "rect";

      # Node style classification.
      nodeStyle =
        entry:
        if (entry.excluded or false) && (entry.replacedBy or null) != null then
          "replaced"
        else if entry.excluded or false then
          "excluded"
        # fx trace: handlers field (list); legacy trace: hasAdapter (bool)
        else if (entry.handlers or [ ]) != [ ] || entry.hasAdapter or false then
          "adapter"
        else if entry.isPolicyDispatch or false then
          "policy"
        else
          "default";

      # Leaf detection done post-mkNode since we need the final node IDs.
      childSet = lib.listToAttrs (
        builtins.concatMap (
          e:
          lib.optional (e.parent != null) {
            name = resolveParentId e.parent (instOf e);
            value = true;
          }
        ) preTagged
      );
      isLeafNode = node: !(childSet ? ${node.id});

      # Edge style classification.
      edgeStyle =
        edge:
        if (edge.excluded or false) && (edge.replacedBy or null) != null then
          "replaced"
        else if edge.excluded or false then
          "excluded"
        else
          "normal";

      inherit (util) nullOr;

      mkNode =
        entry:
        let
          sk = scopeKey entry;
          merged = classesByName.${sk} or [ ];
          perClass = perClassByName.${sk} or { };
        in
        {
          id = seid entry;
          # Short form when unique in this graph, full path otherwise.
          # See displayLabel / displayName / shortLabelCounts.
          label = displayLabel entry;
          # Full "provider/sub/.../name" form. Used by structural operations
          # like foldProviders that need to resolve a provider chain back
          # to its parent node, and by renderers that want to disambiguate
          # when the short label would collide.
          fullLabel = fullName entry;
          # Canonical key matching `identity.pathKey (identity.aspectPath aspect)`.
          pathKey = fullName entry;
          shape = nodeShape entry;
          style = nodeStyle entry;
          entityKind = entry.entityKind or null;
          entityInstance = entry.entityInstance or null;
          # `classes` is the set of classes this aspect contributes to
          # (hasClass = true for each). `class` is the legacy joined-
          # with-`+` single string for renderers that display it.
          # `perClass` is the richer per-class metadata attrset keyed
          # by class name — `perClass.nixos.hasClass`, `.excluded`,
          # `.replacedBy` — for renderers/filters that need class-
          # aware materialization info (e.g. "is this aspect active
          # for the homeConfigurations target?").
          classes = merged;
          class = if merged == [ ] then "" else lib.concatStringsSep "+" (lib.sort (a: b: a < b) merged);
          inherit perClass;
          fnArgNames = nullOr [ ] (entry.fnArgNames or [ ]);
          isParametric = nullOr false (entry.isParametric or false);
          isProvider = nullOr false (entry.isProvider or false);
          providerPath = nullOr [ ] (entry.provider or [ ]);
          hasClass = nullOr false (entry.hasClass or false);
          isExcluded = nullOr false (entry.excluded or false);
          isReplaced = (entry.replacedBy or null) != null;
          isPolicyDispatch = entry.isPolicyDispatch or false;
          policyName = entry.policyName or null;
          from = entry.from or null;
          to = entry.to or null;
        };

      # Chain identities are ctxId-free (see chainIdentity in aspect.nix),
      # so they match entry fullNames directly. Sanitize and use as edge source.
      mkEdge = edge: {
        from = resolveParentId (edge.parent or "") (instOf edge);
        to = seid edge;
        style = edgeStyle edge;
        label = if (edge.excluded or false) && (edge.replacedBy or null) != null then "replaced" else null;
      };

      # Entity kind ids use `ctx_` prefix unconditionally (never collides with
      # mermaid reserved words since the prefix always runs first).
      mkEntityKind = kindName: {
        id = "ctx_${sanitizeChars kindName}";
        name = kindName;
        ctxKeys =
          let
            item = lib.findFirst (i: i.key == kindName) null ctxItems;
          in
          if item != null then item.ctxKeys else [ ];
      };

      # Entity kind transitions: derived from parent→child relationships
      # that cross entity kind boundaries. If an entry in kind B has a parent
      # in kind A (A ≠ B), there's a transition edge A→B.
      entryEntityKindMap = lib.listToAttrs (
        builtins.concatMap (
          e:
          let
            kind = e.entityKind or null;
          in
          lib.optional (kind != null) {
            name = seid e;
            value = kind;
          }
        ) preTagged
      );
      entityEdges = dedupBy (e: "${e.from}->${e.to}") (
        builtins.concatMap (
          e:
          let
            rawParent = e.parent or null;
            parentId = if rawParent == null then "" else resolveParentId rawParent (instOf e);
            parentKind = if rawParent == null then null else (entryEntityKindMap.${parentId} or null);
            childKind = e.entityKind or null;
          in
          lib.optional (parentKind != null && childKind != null && parentKind != childKind) {
            from = "ctx_${sanitizeChars parentKind}";
            to = "ctx_${sanitizeChars childKind}";
            style = "normal";
            label = null;
          }
        ) preTagged
      );

      # Provider-provenance edges: dotted "provided-by" links from provider
      # sub-aspects back to their provider source (e.g. to-hosts → alice,
      # disko/diskoClass → disko).
      providerEdges = lib.concatMap (
        entry:
        let
          prov = entry.provider or [ ];
          providerName = if prov != [ ] then builtins.head prov else null;
          providerEntry = if providerName != null then topLevelEntryByName.${providerName} or null else null;
          # If the provider has a real top-level entry use its full
          # display ID; otherwise fall back to the sanitized bare
          # provider name. The phantom target gets a stub node below.
          # For multi-instance providers, resolve to the same instance as the child.
          providerNodeId =
            if providerEntry != null then
              let
                fn = fullName providerEntry;
                inst = instOf entry;
              in
              if isMultiInstance fn && inst != "" then sanitize "${fn}@${inst}" else sanitize fn
            else
              sanitize providerName;
        in
        lib.optional (prov != [ ] && providerName != "den") {
          from = providerNodeId;
          to = seid entry;
          style = "provide";
          label = "provides";
        }
      ) nodes;

      # Phantom providers: names referenced by `provider` chains that never
      # got their own top-level entry in the trace (e.g. `disko` in a host
      # that only includes `disko/diskoClass` and `disko/diskoImport`
      # directly). The parent aspect definitionally exists — it's
      # defined in the config to host the sub-aspects — so we synthesize
      # a stub node for it so the provider-provenance edges have a
      # properly-labeled target.
      # Policy dispatch edges: connect policy trace entries to the target
      # entity kind subgraph. Uses the entity kind ID (ctx_<kind>) so the
      # edge connects to the kind boundary, not an individual entry.
      policyEdges = lib.concatMap (
        entry:
        let
          isPol = entry.isPolicyDispatch or false;
          targetKind = entry.to or null;
          targetKindId = if targetKind != null then "ctx_${sanitizeChars targetKind}" else null;
          # Only emit if the target kind actually has entries (exists in the graph).
          targetExists = targetKind != null && builtins.any (e: (e.entityKind or null) == targetKind) nodes;
        in
        lib.optional (isPol && targetExists) {
          from = seid entry;
          to = targetKindId;
          style = "policy";
          label = null;
        }
      ) nodes;

      phantomProviderNames = lib.unique (
        lib.concatMap (
          entry:
          let
            prov = entry.provider or [ ];
            providerName = if prov != [ ] then builtins.head prov else null;
          in
          if providerName != null && providerName != "den" && !(topLevelEntryByName ? ${providerName}) then
            [ providerName ]
          else
            [ ]
        ) nodes
      );

      phantomStubEntries = map stubEntry phantomProviderNames;
      rawNodes = map mkNode (lib.sort (a: b: a.name < b.name) (nodes ++ phantomStubEntries));
      # Tag resolution artifact leaves as terminal — these are parametric
      # resolution outputs (e.g., user/resolve(alice,devbox)) that have no
      # children. Regular leaf aspects (networking, demo-shell) keep default style.
      isResolutionArtifact = n: builtins.match ".*/resolve\\(.*" n.label != null;
      finalNodes = map (
        n:
        if isLeafNode n && n.style == "default" && isResolutionArtifact n then
          n // { style = "terminal"; }
        else
          n
      ) rawNodes;

      # All entries were pre-tagged with rootInstance before dedup, so
      # nodes already have correct entityInstance values. No post-hoc
      # tagging needed.
      taggedNodes = finalNodes;

      entityInstanceNames = lib.unique (
        builtins.filter (s: s != null) (map (n: n.entityInstance) taggedNodes)
      );
      entityInstances = map (
        inst:
        let
          parts = lib.splitString ":" inst;
          kind = builtins.head parts;
          name = if builtins.length parts > 1 then lib.concatStringsSep ":" (lib.tail parts) else inst;
        in
        {
          id = sanitize "ctx_${inst}";
          inherit kind name;
          label = if inst == "flake" then "flake" else "${kind}: ${name}";
        }
      ) entityInstanceNames;
    in
    {
      inherit rootName direction;
      rootId = sanitize rootName;
      nodes = taggedNodes;
      edges =
        map mkEdge (
          lib.sort (
            a: b:
            (a.parent or "") < (b.parent or "") || ((a.parent or "") == (b.parent or "") && a.name < b.name)
          ) edges
        )
        ++ providerEdges
        ++ policyEdges;
      entityKinds = map mkEntityKind entityKindNames;
      inherit entityEdges entityInstances;
    };

in
{
  inherit buildGraph emptyNode stubEntry;
}
