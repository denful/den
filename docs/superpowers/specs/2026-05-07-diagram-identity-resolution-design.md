# Diagram Identity Resolution Overhaul

**Date:** 2026-05-07
**Branch:** feat/fx-pipeline
**Status:** Design

---

## Problem

The diagram system's trace handler has not been kept in sync with the fx-pipeline refactors. Three critical data sources are broken:

1. **Entity kind never seeded** — `tracingHandler` uses `deriveEntityKind state` which walks ancestors, but never reads `param.__entityKind` directly. Since no entry is ever seeded with an entity kind, derivation always returns null. All nodes have `entityKind: null`.

2. **ctxTrace never populated** — Initialized to `[]` in `capture.nix` and no handler ever appends to it. The graph builder reads it for entity kind participants and context keys, but it's always empty.

3. **No policy event capture** — The `tracingHandler` only handles `resolve-complete`. It never intercepts `record-fired`, so policy dispatch nodes (`isPolicyDispatch`) are never generated.

**Cascade effects:**
- DAGs have no scope bounding (no subgraphs)
- Sequence diagrams show "no entity kinds captured"
- Policy sequence shows "no policies captured"
- Anonymous nodes get bare `<anon>:N` names (entity-kind disambiguation path requires non-null entityKind)
- Entity transitions (`entityEdges`) are empty

Additionally, the view naming still references "stages" (removed concept) rather than "scopes" (current concept).

---

## Constraints

- `composeHandlers` semantics: tracing handler is `b`, so its **resume wins**. For effects where the real handler's resume matters (like `push-scope` returning `{ scopeHandlers, scopeId }`), we **cannot** add a tracing handler — the resume would be wrong.
- Safe to intercept: `resolve-complete` (already intercepted, resumes `param`), `record-fired` (resumes `null`).
- Unsafe to intercept: `push-scope`, `dispatch-policies`, `emit-policy-effects` (resumes carry computed values).

---

## Design

### 1. Fix entity kind seeding (`trace.nix`)

**Current** (broken):
```nix
entityKind = deriveEntityKind state;
```

**Fixed** — use direct tag first, derive for descendants:
```nix
entityKind =
  let direct = param.__entityKind or null;
  in if direct != null then direct else deriveEntityKind state;
```

The entity resolution boundary aspect (`resolve-schema-entity.nix` line 104) passes `entityKind = param.targetKind` to `push-scope`, and the resolved entity carries `__entityKind`. This seeds the first entry. `deriveEntityKind` then works for all descendant aspects since it can find the seeded ancestor in accumulated entries.

### 2. Populate ctxTrace in resolve-complete (`trace.nix`)

When the resolved entry has a non-null `entityKind`, append a context trace record using scope state:

```nix
ctxEntry = {
  key = entityKind;
  selfName = name;
  entityKind = entityKind;
  ctxKeys = builtins.attrNames (
    ((state.scopeContexts or (_: {})) null).${state.currentScope} or {}
  );
};
```

Append to state, deduplicated by entity kind (one entry per kind is sufficient — the graph builder uses `lib.findFirst` so duplicates are harmless but wasteful):

```nix
isNewKind = !(builtins.any (e: e.key == entityKind) (state.ctxTrace or []));
ctxTrace = (state.ctxTrace or [])
  ++ lib.optional (entityKind != null && isNewKind) ctxEntry;
```

The graph builder already consumes `ctxTrace` to build `entityKinds` and `ctxKeys` for sequence diagram participants.

### 3. Add record-fired handler for policy entries (`trace.nix`)

Add a `record-fired` handler to `tracingHandler`. This effect is safe to intercept (resumes `null`).

```nix
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
      to = null;  # inferred in graph builder
    }) firedNames;
  in {
    resume = null;
    state = state // {
      entries = (state.entries or []) ++ policyEntries;
    };
  };
```

**Policy `to` field:** Set to `null` at trace time. The graph builder already computes `entityEdges` (parent-child relationships crossing entity kind boundaries). After graph construction, policy nodes at entity kind X that have a child entity kind Y transition get `to = Y`. This keeps the trace handler simple and avoids duplicating entity resolution logic.

### 4. Entity instance subgraphs (`graph.nix`, `mermaid.nix`)

**Current:** Graph builder produces `entityKinds` — one entry per kind (e.g., `host`, `user`). Mermaid renderer groups all nodes of a kind into one subgraph.

**New:** Produce `entityInstances` — one entry per entity instance (e.g., `host:laptop`, `user:alice`, `user:bob`). Each instance becomes a separate mermaid subgraph.

**Graph IR change:** Add `entityInstance` field to each node (derived from scope state at trace time). The entity instance identifier is `"${entityKind}:${entityName}"`.

**Entity name derivation** (`resolveEntityName` helper in trace.nix): Extract a human-readable name from the scope context at resolve-complete time. The scope context attrset contains entity bindings like `{ host = { name = "laptop"; ... }; }`. The helper walks known entity kind keys in the context and extracts `.name`:

```nix
resolveEntityName = entityKind: scopeCtx:
  let entity = scopeCtx.${entityKind} or null;
  in if entity != null && entity ? name then entity.name
     else entityKind;  # fallback for custom/unknown entity kinds
```

This handles built-in kinds (`host`, `user`, `home`) which all carry `.name`, and falls back to the bare kind name for custom schema extensions where the entity structure is unknown.

```nix
# New node field
entityInstance = null;  # "host:laptop", "user:alice", etc.
```

**Graph builder:** Build `entityInstances` list from unique `entityInstance` values across nodes:
```nix
entityInstances = [
  { id = "ctx_host_laptop"; kind = "host"; name = "laptop"; label = "host: laptop"; }
  { id = "ctx_user_alice"; kind = "user"; name = "alice"; label = "user: alice"; }
];
```

The graph builder also retains `entityKinds` (one entry per unique kind). Sequence diagrams continue to use `entityKinds` for participants (per-kind, not per-instance). Only the DAG mermaid renderer uses `entityInstances` for subgraph grouping.

**Mermaid renderer:** Replace `entitySubgraph` to iterate `entityInstances` instead of `entityKinds`. Each instance gets its own `subgraph` block.

**Flake context:** Nodes without an entity instance (top-level, flake-scope) get `entityInstance = "flake"` and render in a `flake` subgraph. Nodes inside a scope but with null entityKind (rare — would require no seeded ancestor in the includes chain) also fall into the flake subgraph with a code comment noting this edge case.

### 5. Policy bridge rendering (`mermaid.nix`)

Policy dispatch nodes render as **bridges between entity instance subgraphs**, not inside any subgraph. They are declared at the top level (alongside `unmappedEdges`) with dashed edges connecting the source instance subgraph to the target instance subgraph.

The existing `policyEdges` in the graph builder already connect policy nodes to target entity kind IDs. With entity instances, these connect to the target instance instead.

### 6. Investigate and fix anonymous nodes (`trace.nix`)

With entity kind working, the existing disambiguation fires for most anon nodes:
```nix
"${entityKind}/resolve${aspectTag}${provTag}"
```

For remaining `<anon>:N` nodes:
- **Policy-emitted includes:** Check for `param.meta.__sourcePolicyName` and use `"policy:${policyName}/:${idx}"`.
- **Conditional branches:** `insecure-predicate/<anon>:1,2` etc. — investigate whether these are compile-conditional guard branches. If internal artifacts with no class content, filter them in the `aspectsOnly` filter. If real entities, derive a name from the guard condition or parent context.
- **Schema includes:** Anonymous aspects from `den.schema.*.includes` — derive name from the schema kind.

### 7. Rename views (`views.nix`, `diagrams.nix`)

| Old | New | Title |
|-----|-----|-------|
| `stage-seq` | `scope-seq` | Scope Sequence |
| `stage-seq-full` | `scope-seq-full` | Scope Sequence (expanded) |
| `stage-edges` | `scope-edges` | Scope Topology |

Update `views.nix` view IDs and titles. Update `diagrams.nix` view references.

---

## Files to modify

| File | Change |
|------|--------|
| `nix/lib/aspects/fx/trace.nix` | Fix entityKind seeding, ctxTrace population, record-fired handler, anon naming |
| `nix/lib/diag/graph.nix` | Entity instance grouping, policy `to` inference, `entityInstances` in IR |
| `nix/lib/diag/mermaid.nix` | Entity instance subgraphs, policy bridge rendering, flake context subgraph |
| `nix/lib/diag/sequence.nix` | Keep using `entityKinds` for participants, rename internal functions (`toStageEdgesMermaid` → `toScopeEdgesMermaid` etc.) |
| `nix/lib/diag/views.nix` | Rename stage-* to scope-* |
| `nix/lib/diag/filters/fold.nix` | Update `flattenEntityKinds` to also zero `entityInstances` |
| `nix/lib/diag/filters/reshape.nix` | Update `contextOnly` for entity instances |
| `templates/diagram-demo/modules/diagrams.nix` | Update view references |

---

## Verification

1. `nix develop -c just ci` — all 753 tests pass
2. Build laptop DAG — entity instance subgraphs visible (`host:laptop`, `user:alice`)
3. Build home-alice DAG — home entity instance subgraph visible (`home:alice`)
4. Build laptop scope-seq — entity kind participants with context keys
5. Build laptop policy-seq — policy dispatch nodes with bridge edges
6. No `<anon>:N` nodes without entity kind (except genuine anonymous includes)
7. Regenerate all diagrams via `write-diagrams` — no regressions

---

## Out of scope (follow-up)

- Pipe/quirk flow visualization (new views, not trace issues)
- Fleet policy topology view
- Parametric annotation view
- C4 model updates for entity instances
