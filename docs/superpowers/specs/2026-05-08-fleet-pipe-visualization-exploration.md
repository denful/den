# Fleet & Pipe Visualization — Exploration Notes

**Date:** 2026-05-08
**Context:** fleet-demo template analysis
**Status:** Exploration / prototype

---

## Current gaps

The diagram system captures per-host DAGs starting from `hostContext`. This misses:

1. **Fleet topology** — the `fleet → environment → host` chain from policy-driven entity resolution
2. **Pipe/quirk data flow** — which aspects produce quirk data, which consume it via `pipe.collect`, and how data crosses scope boundaries
3. **Environment grouping** — hosts belonging to `prod` vs `staging` environments

## Data available in the pipeline

### Already traced (via resolve-complete, record-fired)
- Aspects and their parent/child relationships
- Entity kinds and entity instances (host:lb-prod, user:deploy)
- Policy dispatch events (collect-backends, collect-host-addrs, host-to-users)
- Class content per aspect (nixos, homeManager)
- Pipe keys classification (pipeKeys in classify handler)

### Available but not traced
- **`emit-class` with `__isPipeEntry`** — when an aspect emits pipe/quirk data, the `emit-class` effect carries `__isPipeEntry = true` and `class = pipeName`. This tells us which aspects PRODUCE which pipe data.
- **`register-pipe-effect`** — when a policy registers a pipe effect (pipe.collect, pipe.filter, etc.), the effect carries `pipeName`, `stages`, and `sourceScopeId`. This tells us which scopes CONSUME which pipe data and through what transform stages.
- **`push-scope` with `entityKind`** — scope creation events. Already tracked in state but not in trace entries. Would show the fleet → environment → host scope tree.

### Available post-pipeline only (not during trace)
- **`assemblePipes`** output — the actual resolved pipe data after collection. This is computed AFTER the pipeline walk, so the trace handler can't see it.
- **`findMatchingSiblings`** results — which specific hosts matched a `pipe.collect` predicate. Computed during assembly, not during the walk.
- **`scopeParent` tree** — the complete scope hierarchy. Available in pipeline state at the end.

## Proposed enhancements

### Enhancement 1: Trace pipe production (emit-class for pipe keys)

**What:** When `emit-classes` emits a pipe key entry (`__isPipeEntry = true`), record which aspect produced data for which pipe.

**How:** Add handler for `emit-class` in the tracing handler. When `__isPipeEntry = true`, record a pipe production entry:

```nix
"emit-class" = { param, state }:
  let
    isPipe = param.__isPipeEntry or false;
  in {
    resume = null;
    state = state // lib.optionalAttrs isPipe {
      pipeProducers = (state.pipeProducers or []) ++ [{
        pipeName = param.class;
        aspectIdentity = param.identity;
        scope = state.currentScope;
        entityInstance = /* derive from scope */;
      }];
    };
  };
```

**composeHandlers concern:** `emit-class` is handled by `class-collector.nix` (part of defaultHandlers, `a`). Its resume is `null`. Safe to intercept — tracing handler's resume (`null`) matches.

**Graph IR addition:** New edge type `"pipe-produce"` from aspect node → pipe name (virtual node or annotation).

### Enhancement 2: Trace pipe consumption (register-pipe-effect)

**What:** When a policy registers a pipe effect via `register-pipe-effect`, record the consumption relationship.

**How:** Add handler for `register-pipe-effect` in the tracing handler:

```nix
"register-pipe-effect" = { param, state }:
  let
    pipeName = param.pipeName or (param.value.pipeName or null);
    hasCollect = builtins.any (s: (s.__pipeStage or null) == "collect") (param.stages or param.value.stages or []);
  in {
    resume = null;
    state = state // lib.optionalAttrs (pipeName != null) {
      pipeConsumers = (state.pipeConsumers or []) ++ [{
        inherit pipeName hasCollect;
        scope = state.currentScope;
        entityInstance = /* derive from scope */;
        policyName = param.__pipePolicyName or null;
      }];
    };
  };
```

**composeHandlers concern:** `register-pipe-effect` handler resumes `null`. Safe to intercept.

**Graph IR addition:** New edge type `"pipe-collect"` showing cross-scope data flow. For `pipe.collect`, the edge connects consumer scope to all producer scopes (resolved post-pipeline via `scopeParent` sibling analysis).

### Enhancement 3: Scope tree capture for fleet topology

**What:** Capture the complete scope tree (fleet → environment → host → user) from pipeline state after the walk completes.

**How:** This data is already in `state.scopeParent` and `state.scopeContexts` at the end of the pipeline. The capture module can extract it from the final state:

```nix
# In captureWithPathsWith, after rawPerClass:
scopeTree = let
  first = rawPerClass.${lib.head classes};
  parents = (first.state.scopeParent or (_: {})) null;
  contexts = (first.state.scopeContexts or (_: {})) null;
in { inherit parents contexts; };
```

**BUT:** The per-host capture (`hostContext`) starts at the host level — it doesn't have fleet/environment scopes. Those only exist in the full flake-level pipeline run (`fxResolve`).

**Solution:** Add a fleet-level capture that runs the full pipeline from the flake root, not per-host. This would capture the complete scope tree including fleet → environment → host → user.

### Enhancement 4: Fleet-level graph with pipe flows

**What:** A new graph type that shows all hosts, their environment grouping, and pipe data flows between them.

**Structure:**
```
{
  environments = [
    { name = "prod"; hosts = ["lb-prod" "web-prod-1" "web-prod-2"]; }
    { name = "staging"; hosts = ["web-staging"]; }
  ];
  pipes = [
    {
      name = "http-backends";
      producers = [
        { host = "web-prod-1"; aspect = "nginx"; }
        { host = "web-prod-2"; aspect = "nginx"; }
      ];
      consumers = [
        { host = "lb-prod"; aspect = "haproxy"; via = "pipe.collect"; }
      ];
      scope = "environment";  # collection boundary
    }
    {
      name = "host-addrs";
      producers = [
        { host = "lb-prod"; aspect = "hostfile"; }
        { host = "web-prod-1"; aspect = "hostfile"; }
        { host = "web-prod-2"; aspect = "hostfile"; }
      ];
      consumers = [
        { host = "lb-prod"; aspect = "hostfile"; via = "pipe.collect"; }
        { host = "web-prod-1"; aspect = "hostfile"; via = "pipe.collect"; }
        { host = "web-prod-2"; aspect = "hostfile"; via = "pipe.collect"; }
      ];
      scope = "environment";
    }
  ];
}
```

**Data source:** This can be built from post-pipeline state without new trace handlers:
- `scopeParent` → environment grouping
- `scopedPipeEffects` → which scopes have pipe.collect effects
- `scopedClassImports` → which scopes produce pipe data (entries with pipe key names)
- `scopeContexts` → host/environment names for labeling

### Enhancement 5: Sankey/flow diagram for pipe data

**What:** Visualize pipe data flow as a sankey diagram showing data volume/direction between hosts.

**Mermaid sankey-beta:**
```
sankey-beta
web-prod-1,lb-prod,http-backends
web-prod-2,lb-prod,http-backends
lb-prod,web-prod-1,host-addrs
lb-prod,web-prod-2,host-addrs
web-prod-1,lb-prod,host-addrs
web-prod-2,lb-prod,host-addrs
```

The existing `sankey.nix` renderer can be extended with pipe flow data.

## Prioritized approach

### Phase 1: Fleet data enrichment (no trace changes)
- Extend `fleet.nix` to include environment grouping and pipe effect data
- Read `scopedPipeEffects` and `scopedClassImports` from post-pipeline state
- Build pipe flow records showing producer → consumer relationships
- Render as enhanced C4 Context + new pipe flow view

### Phase 2: Trace pipe events (trace handler changes)
- Add `emit-class` handler for pipe production tracking
- Add `register-pipe-effect` handler for pipe consumption tracking
- Add pipe edges to per-host graph IR
- Render pipe produce/consume edges in DAGs

### Phase 3: Fleet-level capture (new capture mode)
- Add fleet-level capture that runs full pipeline from flake root
- Captures complete scope tree including custom entity kinds
- Enables fleet DAG with environment → host → user subgraphs
- Shows policy chains across the full topology

## Key insight

The most impactful visualization doesn't need trace handler changes at all. The post-pipeline state (`scopedPipeEffects`, `scopedClassImports`, `scopeParent`, `scopeContexts`) already contains everything needed to build a fleet pipe flow diagram. We just need to read it and render it.

The per-host DAG enhancements (pipe produce/consume edges) DO need trace changes since the trace happens during the walk, not post-pipeline.
