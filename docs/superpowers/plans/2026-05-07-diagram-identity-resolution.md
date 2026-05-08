# Diagram Identity Resolution Overhaul — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the diagram system's broken trace handler so entity kinds, scope bounding, policy nodes, and sequence diagrams all work again.

**Architecture:** The trace handler (`trace.nix`) needs three fixes: seed entityKind from `param.__entityKind`, populate `ctxTrace` for sequence diagrams, and add a `record-fired` handler for policy nodes. The graph builder (`graph.nix`) needs entity instance grouping. The mermaid renderer needs per-instance subgraphs. View names need updating from "stage" to "scope" vocabulary.

**Tech Stack:** Pure Nix. Tests via nix-unit (`just ci`). Diagrams via mermaid-cli for SVG rendering.

**Spec:** `docs/superpowers/specs/2026-05-07-diagram-identity-resolution-design.md`

---

### Task 1: Fix entity kind seeding and ctxTrace population in trace handler

**Goal:** Make `tracingHandler` produce entries with correct `entityKind` and populate `ctxTrace` for sequence diagrams.

**Files:**
- Modify: `nix/lib/aspects/fx/trace.nix:102-148` (tracingHandler resolve-complete handler)
- Test: `templates/ci/modules/features/fx-trace.nix`

**Acceptance Criteria:**
- [ ] Entity boundary aspects (those with `__entityKind`) produce entries with non-null `entityKind`
- [ ] Descendant aspects inherit `entityKind` via `deriveEntityKind`
- [ ] `ctxTrace` accumulates one entry per entity kind with `{ key, selfName, entityKind, ctxKeys }`
- [ ] ctxTrace entries are deduplicated by entity kind
- [ ] Existing trace tests still pass

**Verify:** `nix develop -c just ci fx-trace` → summary line shows all pass

**Steps:**

- [ ] **Step 1: Fix entityKind and add ctxTrace in tracingHandler, then write test**

Note: The test and implementation are done together because the ctxTrace assertions depend on the ctxTrace implementation. Write the implementation first, then the test.

- [ ] **Step 2: Fix entityKind in tracingHandler**

In `nix/lib/aspects/fx/trace.nix`, in the `tracingHandler` function's `resolve-complete` handler, change:

```nix
# Old (line ~108):
entityKind = deriveEntityKind state;
```

to:

```nix
entityKind =
  let direct = param.__entityKind or null;
  in if direct != null then direct else deriveEntityKind state;
```

- [ ] **Step 3: Add ctxTrace population**

In the same handler, after computing `entityKind` and `name`, add ctxTrace logic. Add a `resolveEntityName` helper above the handler:

```nix
resolveEntityName = ek: scopeCtx:
  let entity = scopeCtx.${ek} or null;
  in if entity != null && entity ? name then entity.name
     else ek;
```

Then in the state update section, add:

```nix
scope = state.currentScope;
scopeCtx = if scope == null then {} else ((state.scopeContexts or (_: {})) null).${scope} or {};
isNewKind = !(builtins.any (e: e.key == entityKind) (state.ctxTrace or []));
ctxEntry = {
  key = entityKind;
  selfName = resolveEntityName entityKind scopeCtx;
  entityKind = entityKind;
  ctxKeys = builtins.attrNames scopeCtx;
};
```

And in the state merge:

```nix
state = state // {
  entries = (state.entries or []) ++ [ entry ];
} // lib.optionalAttrs (entityKind != null && isNewKind) {
  ctxTrace = (state.ctxTrace or []) ++ [ ctxEntry ];
};
```

- [ ] **Step 4: Write test for entityKind seeding and ctxTrace**

Add to `templates/ci/modules/features/fx-trace.nix`:

```nix
test-tracingHandler-entity-kind-seeded = denTest (
  { den, ... }:
  let
    entity = {
      name = "host";
      __entityKind = "host";
      meta = { provider = []; };
      nixos = { a = 1; };
      includes = [
        {
          name = "child";
          meta = { provider = []; };
          nixos = { b = 2; };
          includes = [];
        }
      ];
    };
    result = den.lib.aspects.fx.pipeline.mkPipeline {
      class = "nixos";
      extraHandlers = den.lib.aspects.fx.trace.tracingHandler "nixos";
      extraState = { entries = []; ctxTrace = []; };
    } {
      self = entity // { into = _: {}; provides = {}; };
      ctx = {};
    };
    hostEntry = lib.findFirst (e: e.name == "host") null result.state.entries;
    childEntry = lib.findFirst (e: e.name == "child") null result.state.entries;
  in {
    expr = {
      hostEntityKind = hostEntry.entityKind;
      childEntityKind = childEntry.entityKind;
      ctxTraceLength = builtins.length result.state.ctxTrace;
      ctxTraceKey = (builtins.head result.state.ctxTrace).key;
    };
    expected = {
      hostEntityKind = "host";
      childEntityKind = "host";
      ctxTraceLength = 1;
      ctxTraceKey = "host";
    };
  }
);
```

- [ ] **Step 5: Run tests, format, and commit**

Run: `nix develop -c just fmt && nix develop -c just ci fx-trace`
Expected: All tests PASS including the new entityKind test.

```bash
git add nix/lib/aspects/fx/trace.nix templates/ci/modules/features/fx-trace.nix
git commit -m "fix(diag): seed entityKind from param.__entityKind, populate ctxTrace"
```

---

### Task 2: Add record-fired handler for policy trace entries

**Goal:** Capture fired policy names as trace entries so the graph builder can create policy dispatch nodes.

**Files:**
- Modify: `nix/lib/aspects/fx/trace.nix` (add `record-fired` to tracingHandler)
- Test: `templates/ci/modules/features/fx-trace.nix`

**Acceptance Criteria:**
- [ ] `tracingHandler` returns a handler set with both `resolve-complete` and `record-fired`
- [ ] Fired policies produce entries with `isPolicyDispatch = true`, `policyName`, `from`, `entityKind`
- [ ] `to` is `null` (inferred later in graph builder)
- [ ] Composing with `defaultHandlers` doesn't break `record-fired` resume (must be `null`)

**Verify:** `nix develop -c just ci fx-trace` → all pass

**Steps:**

- [ ] **Step 1: Write test for record-fired handler**

Add to `templates/ci/modules/features/fx-trace.nix`:

```nix
# Test that tracingHandler's record-fired creates policy entries
test-tracingHandler-record-fired = denTest (
  { den, ... }:
  let
    fx = den.lib.fx;
    comp = fx.send "record-fired" {
      entityKind = "host";
      firedPolicies = { host-to-users = true; host-to-default = true; };
    };
    result = fx.handle {
      handlers = den.lib.aspects.fx.pipeline.composeHandlers
        (den.lib.aspects.fx.pipeline.defaultHandlers { class = "nixos"; ctx = {}; })
        (den.lib.aspects.fx.trace.tracingHandler "nixos");
      state = den.lib.aspects.fx.pipeline.defaultState // {
        entries = []; ctxTrace = [];
      };
    } comp;
    policyEntries = builtins.filter (e: e.isPolicyDispatch or false) result.state.entries;
    policyNames = lib.sort (a: b: a < b) (map (e: e.policyName) policyEntries);
  in {
    expr = {
      count = builtins.length policyEntries;
      names = policyNames;
      fromKind = (builtins.head policyEntries).from;
      toIsNull = (builtins.head policyEntries).to == null;
    };
    expected = {
      count = 2;
      names = [ "host-to-default" "host-to-users" ];
      fromKind = "host";
      toIsNull = true;
    };
  }
);
```

- [ ] **Step 2: Add record-fired handler to tracingHandler**

In `nix/lib/aspects/fx/trace.nix`, change `tracingHandler` from returning a single-key handler set to a two-key handler set. Add `record-fired` alongside `resolve-complete`:

```nix
tracingHandler = class: {
  "resolve-complete" = { param, state }: /* ... existing handler ... */;

  "record-fired" = { param, state }:
    let
      firedNames = builtins.attrNames param.firedPolicies;
      policyEntries = map (policyName: {
        name = policyName;
        class = "";
        parent = null;
        provider = [];
        excluded = false;
        excludedFrom = null;
        replacedBy = null;
        isProvider = false;
        handlers = [];
        hasClass = false;
        isParametric = false;
        fnArgNames = [];
        entityKind = param.entityKind;
        isPolicyDispatch = true;
        policyName = policyName;
        from = param.entityKind;
        to = null;
      }) firedNames;
    in {
      resume = null;
      state = state // {
        entries = (state.entries or []) ++ policyEntries;
      };
    };
};
```

- [ ] **Step 3: Run tests and commit**

Run: `nix develop -c just fmt && nix develop -c just ci fx-trace`
Expected: All tests PASS.

```bash
git add nix/lib/aspects/fx/trace.nix templates/ci/modules/features/fx-trace.nix
git commit -m "feat(diag): add record-fired handler to capture policy dispatch entries"
```

---

### Task 3: Add entity instance tracking to trace entries and graph IR

**Goal:** Each trace entry carries an `entityInstance` field (e.g., `"host:laptop"`) so the graph builder can group nodes by specific entity instances. The graph IR gains an `entityInstances` list.

**Files:**
- Modify: `nix/lib/aspects/fx/trace.nix:102-148` (add `entityInstance` to entry)
- Modify: `nix/lib/diag/graph.nix:23-51` (add `entityInstance` to `emptyNode` and `stubEntry`)
- Modify: `nix/lib/diag/graph.nix:100-493` (build `entityInstances` list in `buildGraph`, add `entityInstance` to `mkNode`)
- Modify: `nix/lib/diag/json.nix:41-51` (add `entityInstances` to serialized output)

**Acceptance Criteria:**
- [ ] Trace entries include `entityInstance` field (e.g., `"host:laptop"` or `null`)
- [ ] `emptyNode` and `stubEntry` have `entityInstance = null`
- [ ] `buildGraph` output includes `entityInstances` list with `{ id, kind, name, label }` records
- [ ] `buildGraph` output retains `entityKinds` for sequence diagram compatibility
- [ ] Nodes without entity kind get `entityInstance = "flake"` when there are other entity instances in the graph

**Verify:** `nix develop -c just ci fx-trace` → all pass; `nix build --override-input den . ./templates/diagram-demo#laptop-ir --no-link --print-out-paths` → IR JSON has `entityInstances` array with entries

**Steps:**

- [ ] **Step 1: Add entityInstance to trace entries**

In `nix/lib/aspects/fx/trace.nix`, in the `tracingHandler`'s `resolve-complete` handler, compute `entityInstance` alongside `entityKind`:

```nix
entityInstance =
  if entityKind != null then
    let
      scope = state.currentScope;
scopeCtx = if scope == null then {} else ((state.scopeContexts or (_: {})) null).${scope} or {};
      eName = resolveEntityName entityKind scopeCtx;
    in "${entityKind}:${eName}"
  else null;
```

Add `inherit entityInstance;` to the entry record.

Also add `entityInstance` to the `record-fired` policy entries, using the same derivation from state at that point.

- [ ] **Step 2: Add entityInstance to graph.nix emptyNode/stubEntry**

In `nix/lib/diag/graph.nix`, add to `emptyNode` (after `entityKind = null;`):

```nix
entityInstance = null;
```

Add the same to `stubEntry`.

- [ ] **Step 3: Add entityInstance to mkNode and build entityInstances list**

In `buildGraph`, after computing `mkNode`, read `entityInstance` from the entry:

```nix
mkNode = entry:
  let
    # ... existing code ...
  in {
    # ... existing fields ...
    entityInstance = entry.entityInstance or null;
  };
```

After `finalNodes`, build `entityInstances`:

```nix
# Assign "flake" instance to unscoped nodes when entity instances exist.
hasAnyInstances = builtins.any (n: n.entityInstance != null) finalNodes;
taggedNodes = if hasAnyInstances then
  map (n: if n.entityInstance == null then n // { entityInstance = "flake"; } else n) finalNodes
else finalNodes;

entityInstanceNames = lib.unique (
  builtins.filter (s: s != null) (map (n: n.entityInstance) taggedNodes)
);
entityInstances = map (inst:
  let
    parts = lib.splitString ":" inst;
    kind = builtins.head parts;
    name = if builtins.length parts > 1 then lib.concatStringsSep ":" (lib.tail parts) else inst;
  in {
    id = sanitize "ctx_${inst}";
    inherit kind name;
    label = if inst == "flake" then "flake" else "${kind}: ${name}";
  }
) entityInstanceNames;
```

Update the return record:

```nix
{
  inherit rootName direction;
  rootId = sanitize rootName;
  nodes = taggedNodes;  # was: finalNodes
  edges = /* ... unchanged ... */;
  entityKinds = map mkEntityKind entityKindNames;  # retained for sequence diagrams
  inherit entityEdges entityInstances;
}
```

- [ ] **Step 4: Update json.nix to serialize entityInstances**

In `nix/lib/diag/json.nix`, add `entityInstances` to the `toJSON` function's output record (line 49, after `entityEdges`):

```nix
entityInstances = g.entityInstances or [];
```

- [ ] **Step 5: Also add entityInstance to record-fired entries**

In `nix/lib/aspects/fx/trace.nix`, update the `record-fired` handler's policy entries to include `entityInstance`:

```nix
scope = state.currentScope;
scopeCtx = if scope == null then {} else ((state.scopeContexts or (_: {})) null).${scope} or {};
entityInstance =
  if param.entityKind != null then
    "${param.entityKind}:${resolveEntityName param.entityKind scopeCtx}"
  else null;
```

Add `inherit entityInstance;` to each policy entry.

- [ ] **Step 6: Run tests and verify IR output**

Run: `nix develop -c just fmt && nix develop -c just ci fx-trace`
Then: `nix build --override-input den . ./templates/diagram-demo#laptop-ir --no-link --print-out-paths` and inspect the JSON for `entityInstances`.

```bash
git add nix/lib/aspects/fx/trace.nix nix/lib/diag/graph.nix nix/lib/diag/json.nix
git commit -m "feat(diag): add entityInstance tracking to trace entries and graph IR"
```

---

### Task 4: Update mermaid renderer for entity instance subgraphs and policy bridges

**Goal:** DAG diagrams group nodes into per-instance subgraphs (`host:laptop`, `user:alice`) with policy nodes as bridges between them.

**Files:**
- Modify: `nix/lib/diag/mermaid.nix:70-275` (replace `entitySubgraph` with instance-based grouping, update policy edge rendering)

**Acceptance Criteria:**
- [ ] DAG renders `subgraph` blocks per entity instance (e.g., `host: laptop`, `user: alice`)
- [ ] Unscoped nodes render in a `flake` subgraph
- [ ] Policy dispatch nodes render outside all subgraphs with bridge edges
- [ ] Cross-instance edges render at top level
- [ ] Flat views (no entity instances) still work correctly

**Verify:** `nix build --override-input den . ./templates/diagram-demo#laptop-dag --no-link --print-out-paths` → DAG contains `subgraph` blocks with entity instance labels

**Steps:**

- [ ] **Step 1: Replace entitySubgraph with instanceSubgraph**

In `nix/lib/diag/mermaid.nix`, replace the `entitySubgraph` function and related code. The key changes:

Replace `hasEntityKinds` with:
```nix
hasEntityInstances = graph.entityInstances or [] != [];
```

Replace `entitySubgraph` with:
```nix
instanceSubgraph = inst:
  let
    instNodes = builtins.filter (n:
      n.entityInstance == "${inst.kind}:${inst.name}"
      && n.id != rootId
      && !(n.isPolicyDispatch or false)
    ) nodes;
    instEdges = builtins.filter (e:
      let
        fromNode = nodeById.${e.from} or null;
        toNode = nodeById.${e.to} or null;
        fromInst = if fromNode != null then fromNode.entityInstance else null;
        toInst = if toNode != null then toNode.entityInstance else null;
        thisInst = "${inst.kind}:${inst.name}";
      in
      fromNode != null
      && fromInst == thisInst
      && (toInst == null || toInst == thisInst)
      && (e.style or "normal") != "policy"
    ) edges;
  in
  lib.optional (instNodes != []) (
    "  subgraph ${inst.id}[\"${inst.label}\"]\n"
    + lib.concatMapStringsSep "\n" nodeDecl instNodes
    + "\n"
    + lib.concatMapStringsSep "\n" edgeDecl instEdges
    + "\n  end"
  );
```

- [ ] **Step 2: Update topLevelNodes and unmappedEdges for instances**

```nix
topLevelNodes =
  if hasEntityInstances then
    builtins.filter (n:
      n.entityInstance == null
      && n.id != rootId
      && !(n.isPolicyDispatch or false)
    ) nodes
  else
    builtins.filter (n: n.id != rootId) nodes;

policyNodes = builtins.filter (n: n.isPolicyDispatch or false) nodes;

unmappedEdges = builtins.filter (e:
  let
    fromNode = nodeById.${e.from} or null;
    toNode = nodeById.${e.to} or null;
    fromInst = if fromNode != null then fromNode.entityInstance else null;
    toInst = if toNode != null then toNode.entityInstance else null;
    isCrossInst = fromInst != null && toInst != null && fromInst != toInst;
  in
  (fromNode != null && fromInst == null)
  || (isCrossInst && (e.style or "normal") != "policy")
) edges;
```

- [ ] **Step 3: Update the diagram assembly**

Replace the `hasEntityKinds` branch in the final `renderMermaid` call with `hasEntityInstances`:

```nix
if hasEntityInstances then
  lib.concatMap instanceSubgraph (graph.entityInstances or [])
  ++ [ "" ]
  ++ map nodeDecl policyNodes
  ++ map edgeDecl (builtins.filter (e: (e.style or "normal") == "policy") edges)
  ++ map edgeDecl unmappedEdges
else
  map edgeDecl edges
```

Update `kindSuffix` to use `entityInstance` instead of `entityKind` for flat views. Update the subgraph style lines to iterate `entityInstances` instead of `entityKinds`.

- [ ] **Step 4: Verify and commit**

Run: `nix develop -c just fmt`
Then: `nix build --override-input den . ./templates/diagram-demo#laptop-dag --no-link --print-out-paths` and read the output.
Expected: Mermaid source contains `subgraph ctx_host_laptop["host: laptop"]` and similar blocks.

```bash
git add nix/lib/diag/mermaid.nix
git commit -m "feat(diag): render entity instance subgraphs with policy bridges"
```

---

### Task 5: Investigate and fix anonymous nodes

**Goal:** Determine what the `host/<anon>:3`, `user/<anon>:2`, `insecure-predicate/<anon>:1` nodes actually are, then either prune internal artifacts or enrich their labels.

**Files:**
- Modify: `nix/lib/aspects/fx/trace.nix` (improve anon naming with entityKind now working)
- Possibly modify: `nix/lib/diag/filters/predicate.nix` or `fold.nix` (if pruning needed)

**Acceptance Criteria:**
- [ ] Anonymous nodes that are entity resolution boundaries get `entityKind/resolve(ctxAspect)` names
- [ ] Anonymous nodes from policy-emitted includes get `policy:<name>` prefix where possible
- [ ] Pure internal plumbing nodes (no class content, no children) are identified and documented
- [ ] `insecure-predicate/<anon>:1,2` nodes are explained and either named or pruned

**Verify:** `nix build --override-input den . ./templates/diagram-demo#laptop-dag --no-link --print-out-paths` → no unexplained `<anon>:N` nodes

**Steps:**

- [ ] **Step 1: Verify entityKind disambiguation now works**

After Task 1, rebuild the laptop DAG and check which anon nodes remain. Many should now have `entityKind/resolve(...)` names since entityKind is no longer null.

Read the IR JSON and list remaining anonymous nodes. For each, check:
- Does it have class content (`hasClass`)? → real entity, needs a name
- Does it have children in the edge list? → structural node, needs a name
- Neither? → plumbing artifact, candidate for pruning

- [ ] **Step 2: Investigate insecure-predicate/unfree-predicate anon children**

Read the demo aspects that define `insecure-predicate` and `unfree-predicate` in `templates/diagram-demo/modules/aspects/den.nix`. Check if their `includes` contain anonymous functions (compile-conditional guards). The `<anon>:N` children are likely the guard branches.

If they are conditional guard branches with no class content: these are structural artifacts of `compile-conditional`. They should be folded out in the `foldWrappers` filter or the existing `aspectsOnly` filter.

If they have class content: they need names derived from their parent and role.

- [ ] **Step 3: Improve naming for remaining anon nodes**

In `nix/lib/aspects/fx/trace.nix`, after the existing entity-kind disambiguation block, add handling for policy-sourced aspects:

```nix
else if isAnon && (param.__sourcePolicyName or null) != null then
  "policy:${param.__sourcePolicyName}"
```

Verify `__sourcePolicyName` propagation: check `nix/lib/aspects/fx/policy/classify.nix` for where this is tagged.

- [ ] **Step 4: Commit findings and fixes**

Document which anon nodes were real vs artifacts. Commit the naming improvements.

```bash
git add nix/lib/aspects/fx/trace.nix
git commit -m "fix(diag): improve anonymous node naming with entityKind disambiguation"
```

---

### Task 6: Rename views from "stage" to "scope" vocabulary

**Goal:** Update view identifiers, titles, and internal function names from the removed "stage" concept to "scope".

**Files:**
- Modify: `nix/lib/diag/views.nix:96-108,162-166` (view IDs and titles)
- Modify: `nix/lib/diag/sequence.nix:319-359` (rename `toStageEdgesMermaid` → `toScopeEdgesMermaid`)
- Modify: `nix/lib/diag/default.nix:208-210` (renderer spec key)
- Modify: `templates/diagram-demo/modules/diagrams.nix` (if it references stage-* views)

**Acceptance Criteria:**
- [ ] `stage-seq` → `scope-seq`, `stage-seq-full` → `scope-seq-full`, `stage-edges` → `scope-edges`
- [ ] View titles updated: "Stage Sequence" → "Scope Sequence" etc.
- [ ] Internal function `toStageEdgesMermaid` → `toScopeEdgesMermaid` (and `With` variant)
- [ ] Renderer spec key in `default.nix` updated
- [ ] No remaining "stage" references in view/sequence code (except comments explaining the rename)

**Verify:** `nix build --override-input den . ./templates/diagram-demo#laptop-scope-seq --no-link --print-out-paths` → builds successfully with "Scope Sequence" title

**Steps:**

- [ ] **Step 1: Rename in views.nix**

```nix
# Line 96-108: rename view IDs and titles
view = "scope-seq";
title = "Scope Sequence";
altText = "Scope sequence";

view = "scope-seq-full";
title = "Scope Sequence (expanded)";
altText = "Scope sequence expanded";

# Line 162-166: extended views
view = "scope-edges";
title = "Scope Topology";
altText = "Scope edges";
```

- [ ] **Step 2: Rename in sequence.nix**

Rename the functions and their `With` variants:
- `toStageEdgesMermaidWith` → `toScopeEdgesMermaidWith`
- `toStageEdgesMermaid` → `toScopeEdgesMermaid`

Update the export block at the bottom of the file.

- [ ] **Step 3: Update default.nix renderer spec**

In `nix/lib/diag/default.nix`, line 208-210:

```nix
# Old:
toStageEdgesMermaid = { withFn = sequence.toStageEdgesMermaidWith; mc = true; };
# New:
toScopeEdgesMermaid = { withFn = sequence.toScopeEdgesMermaidWith; mc = true; };
```

- [ ] **Step 4: Update diagram-demo template if needed**

Check `templates/diagram-demo/modules/diagrams.nix` for any references to `stage-seq`, `stage-seq-full`, or `stage-edges` view names and update them.

- [ ] **Step 5: Run full CI and commit**

Run: `nix develop -c just fmt && nix develop -c just ci`
Expected: All tests pass. The diagram packages now use `scope-seq` etc.

Note: Also check `diagrams.nix` README text (writeText derivation) for hardcoded `stage-seq` strings in the output table and update them.

Note: Package names change from `laptop-stage-seq` to `laptop-scope-seq`. This is acceptable since the branch hasn't shipped.

```bash
git add nix/lib/diag/views.nix nix/lib/diag/sequence.nix nix/lib/diag/default.nix templates/diagram-demo/modules/diagrams.nix
git commit -m "refactor(diag): rename stage-* views to scope-* vocabulary"
```

---

### Task 7: Update filters for entityInstances and run full verification

**Goal:** Ensure all graph filters handle the new `entityInstances` field, then do a full verification pass.

**Files:**
- Modify: `nix/lib/diag/filters/fold.nix:178-185` (`flattenEntityKinds`)
- Modify: `nix/lib/diag/filters/reshape.nix:20-49` (`contextOnly`)
- Modify: `nix/lib/diag/filters/closure.nix:25-35` (`neighborhoodOf`)
- Modify: `nix/lib/diag/filters/predicate.nix:55-62` (if it zeros entityKinds)
- Modify: `nix/lib/diag/filters/diff.nix:80-85` (carry entityInstances)

**Acceptance Criteria:**
- [ ] `flattenEntityKinds` also zeros `entityInstances` and nulls `entityInstance` on nodes
- [ ] `contextOnly` handles entity instances (or zeros them since it replaces all nodes)
- [ ] `neighborhoodOf` zeros `entityInstances`
- [ ] `diffGraphs` carries `entityInstances` from the `a` graph
- [ ] Predicate filters zero `entityInstances`
- [ ] All diagram packages build without errors
- [ ] Full CI passes

**Verify:** `nix develop -c just ci` → all pass; `nix run --override-input den . ./templates/diagram-demo#write-diagrams` → regenerates all diagrams successfully

**Steps:**

- [ ] **Step 1: Update flattenEntityKinds**

In `nix/lib/diag/filters/fold.nix`:

```nix
flattenEntityKinds = graph:
  graph // {
    nodes = map (n: n // { entityKind = null; entityInstance = null; }) graph.nodes;
    entityKinds = [];
    entityEdges = [];
    entityInstances = [];
  };
```

- [ ] **Step 2: Update contextOnly**

In `nix/lib/diag/filters/reshape.nix`, `contextOnly` replaces all nodes, so add:

```nix
entityInstances = [];
```

to the result attrset.

- [ ] **Step 3: Update neighborhoodOf and closure filters**

In `nix/lib/diag/filters/closure.nix`, `neighborhoodOf` already zeros `entityKinds` and `entityEdges`. Add:

```nix
entityInstances = [];
```

- [ ] **Step 4: Update diffGraphs**

In `nix/lib/diag/filters/diff.nix`, carry `entityInstances` from graph `a`:

```nix
entityInstances = a.entityInstances or [];
```

- [ ] **Step 5: Update predicate filters**

In `nix/lib/diag/filters/predicate.nix`, add `entityInstances = [];` where `entityKinds = [];` already appears.

- [ ] **Step 6: Full CI and regenerate diagrams**

Run: `nix develop -c just fmt && nix develop -c just ci`
Expected: All 753+ tests pass.

Run: `nix run --override-input den . ./templates/diagram-demo#write-diagrams`
Expected: All diagrams regenerate without errors.

Verify key outputs:
- `laptop-dag` has entity instance subgraphs
- `laptop-scope-seq` has entity kind participants
- `laptop-policy-seq` has policy dispatch nodes
- `home-alice-dag` has home entity instance subgraph

```bash
git add nix/lib/diag/filters/
git commit -m "fix(diag): update filters to handle entityInstances field"
```

---

## Task Dependencies

```
Task 1 (entityKind + ctxTrace)
  ↓
Task 2 (record-fired)
  ↓
Task 3 (entityInstance in trace + graph IR)
  ↓
Task 4 (mermaid renderer)     Task 5 (anon nodes)     Task 6 (view rename)
  ↓                              ↓                        ↓
Task 7 (filters + full verification)
```

Tasks 4, 5, and 6 can run in parallel after Task 3. Task 7 depends on all of them.
