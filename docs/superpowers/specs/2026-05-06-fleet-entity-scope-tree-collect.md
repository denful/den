# Fleet Entity and Scope-Tree Collect

**Date:** 2026-05-06
**Status:** Design
**Supersedes:** `mkGlobalPipePool` in resolve.nix, `docs/superpowers/fleet-entity-migration.md`

---

## Problem

`pipe.collect` currently uses `mkGlobalPipePool` — a separate function that runs `mkPipeline` for every host, merges state with naive `//`, and passes the result as a read-only pool to `assemblePipes`. This has three issues:

1. **O(2N) pipeline runs** — each host's pipeline runs twice (once for pool, once for its own resolve)
2. **Shadow path** — manually replicates mkPipeline setup, must stay in sync with fxResolve
3. **Scope ID collision** — naive `//` merge silently clobbers shared entities

More fundamentally: `pipe.collect` should operate within the pipeline's own scope tree, not a separate external pool. Users should be able to collect from any sibling scope — peer users on the same host, peer hosts under a fleet, peer hosts under an environment — using the same mechanism.

## Solution

Two changes:

1. **`pipe.collect` iterates sibling scopes** within the current walk's state (`scopeContexts`, `scopeParent`, `scopedClassImports`). No external pool.

2. **Hosts are walked, not just instantiated.** `to-os-outputs` emits `resolve.to "host"` + `instantiate` instead of just `instantiate`. This puts host scopes into the walk's state. `applyInstantiates` reads pre-walked modules from `perScope` instead of triggering per-host `fxResolve`.

Fleet is an optional user-defined grouping entity that adds a parent scope for topology control.

## Scope-tree collect

`collectFromPeers` is rewritten to iterate sibling scopes:

```
collectFromPeers(currentScopeId, pipeName, predicate):
  parent = scopeParent[currentScopeId]
  siblings = scopes where scopeParent[sid] == parent AND sid != currentScopeId
  matching = filter(sid: predicate(scopeContexts[sid])) siblings
  return concatMap(sid: scopedClassImports[sid][pipeName]) matching
```

Uses the walk's own `scopeContexts`, `scopeParent`, `scopedClassImports`. No `globalPipePool` parameter.

### Entity kind filtering algorithm

A predicate `({ host, ... }: true)` should match host scopes but NOT user scopes — even though user scopes also have `host` in context (inherited from parent). The filter:

1. Compute `predEntityArgs` = required args of predicate that are members of `schemaEntityKinds`
2. For each sibling scope, compute `scopeEntityArgs` = keys in scope context that are members of `schemaEntityKinds`
3. **Reject** if `scopeEntityArgs` has entity kinds NOT in `predEntityArgs` (scope is deeper than predicate targets)

```nix
entityKinds = den.lib.schemaUtil.schemaEntityKinds;  # e.g., ["host" "user" "home"]
predArgs = builtins.functionArgs predicate;
requiredArgs = filter (k: !predArgs.${k}) (attrNames predArgs);
predEntityArgs = filter (k: elem k entityKinds) requiredArgs;

predicateMatches = sid:
  let
    ctx = scopeContexts.${sid};
    hasRequired = all (k: ctx ? ${k}) requiredArgs;
    scopeEntityArgs = filter (k: ctx ? ${k}) entityKinds;
    extraEntityKinds = filter (k: !elem k predEntityArgs) scopeEntityArgs;
  in
  hasRequired && extraEntityKinds == [] && predicate ctx;
```

### Why this works for custom entity kinds

`schemaEntityKinds` = kinds with `isEntity = true` — these are structural entities that have aspect evaluation and self-provide (host, user, home). Routing kinds (fleet, environment, flake-system) have `isEntity = false` and are **transparent** to the filter.

The depth hierarchy is: routing kinds organize the tree, entity kinds define the depth. A host scope has `{ host }` in entity kinds. A user scope has `{ host, user }`. The filter rejects scopes with entity kinds the predicate didn't request — regardless of what entity kinds exist or their declared order.

Custom entity kinds with `isEntity = true` (e.g., a `container` kind with its own aspect evaluation) naturally join this hierarchy. A predicate `({ host, ... }: true)` would reject a scope with `{ host, container }` because `container` is an extra entity kind.

Custom routing kinds (e.g., `environment`) have `isEntity = false`, so they're invisible to the filter. A scope with `{ environment, host }` passes the `{ host, ... }:` predicate because `environment` isn't in `schemaEntityKinds`.

### Sibling-only vs descendant collect

`pipe.collect` is sibling-only by design. For fleet-level aggregation across descendants (e.g., fleet consumer reading all hosts across environments), use `pipe.expose` composition:

```nix
# Hosts expose data up to environment
den.policies.host-expose = { environment, host, ... }:
  let inherit (den.lib.policy) pipe; in
  [ (pipe.from "http-backends" [ pipe.expose ]) ];

# Environments expose data up to fleet
den.policies.env-expose = { fleet, environment, ... }:
  let inherit (den.lib.policy) pipe; in
  [ (pipe.from "http-backends" [ pipe.expose ]) ];
```

`pipe.expose` pushes UP, `pipe.collect` pulls SIDEWAYS. These are complementary:
- Same-level peer discovery → `pipe.collect`
- Cross-level aggregation → `pipe.expose` chains

## Walk-then-instantiate

The current `to-os-outputs` policy emits only `instantiate` effects, which trigger separate per-host `fxResolve` calls inside `evalModules`. Each host gets an isolated walk that can't see peers.

Changed to emit both `resolve.to` and `instantiate`:

```nix
den.policies.to-os-outputs = { system, ... }:
  let hosts = den.hosts.${system} or {};
  in lib.concatMap (host:
    lib.optionals (host.intoAttr != []) [
      (resolve.to "host" { inherit host; })
      (den.lib.policy.instantiate host)
    ]
  ) (builtins.attrValues hosts);

den.policies.to-hm-outputs = { system, ... }:
  let homes = den.homes.${system} or {};
  in lib.concatMap (home:
    lib.optionals (home.intoAttr != []) [
      (resolve.to "home" { inherit home; })
      (den.lib.policy.instantiate home)
    ]
  ) (builtins.attrValues homes);
```

`resolve.to "host"` walks the host within the current pipeline, populating `scopeContexts` and `scopedClassImports` with host and user scopes. Same pattern for homes. `instantiate` effects are collected as before.

`applyInstantiates` (phase 4) signature changes to receive `perScope` from phase 1:

```nix
applyInstantiates = scopedInstantiates: perScope: classImports:
```

For each instantiate spec, find the host's scope ID via `mkScopeId` of the host's scope context (same function used by `push-scope` handler during the walk). Then read pre-walked modules:

```nix
hostScopeId = mkScopeId { host = spec.hostConfig; };  # or stored on spec during walk
hostModules = perScope.${hostScopeId}.${spec.class or "nixos"} or [];
evaluated = spec.instantiate { modules = hostModules; };
```

Pipe data is already baked into `hostModules` — applied during `wrapPerScope` via augmented scope contexts from `assemblePipes`.

Per-host `fxResolve` is eliminated. One walk produces everything.

### Scope ID matching

The `register-instantiate` handler already stores the spec at a specific scope. During the walk, `resolve.to "host"` creates a host scope and `instantiate` fires at the same scope. The instantiate spec should carry `sourceScopeId` (same pattern as `register-route` and `register-provide`). Then `applyInstantiates` uses `spec.sourceScopeId` directly — no need to recompute `mkScopeId`.

### Walk chain

```
OLD:  flake → flake-system → instantiate(host) → [separate fxResolve per host]
NEW:  flake → flake-system → resolve.to(host) + instantiate(host) → [reads from walk output]
```

Without fleet, hosts are siblings under `flake-system`. `pipe.collect ({ host, ... }: true)` sees all peer hosts.

## Fleet as optional grouping

Den provides an empty `fleet` schema slot:

```nix
# modules/options.nix, schema defaults:
config.den.schema.fleet = {};
```

Users opt into fleet by wiring policies — same mechanism as any grouping entity:

```nix
# Fires at flake scope (scoped by den.schema.flake.includes)
den.policies.to-fleet = { ... }:
  [ (resolve.to "fleet" { fleet = { name = "fleet"; }; }) ];

den.policies.fleet-to-hosts = { fleet, ... }:
  lib.concatMap (system:
    lib.concatMap (hostName:
      let host = den.hosts.${system}.${hostName}; in [
        (resolve.to "host" { inherit host; })
        (den.lib.policy.instantiate host)
      ]
    ) (builtins.attrNames (den.hosts.${system} or {}))
  ) (builtins.attrNames (den.hosts or {}));

den.schema.flake.includes = [ den.policies.to-fleet ];
den.schema.fleet.includes = [ den.policies.fleet-to-hosts ];
```

Fleet lives at the `flake` level (above `flake-system`) so it encompasses all architectures.

`{ fleet, ... }:` matches fleet scope — same convention as `{ host, ... }:`. The `resolve.to "fleet" { fleet = { name = "fleet"; }; }` puts `fleet` in scope context.

### User-defined groupings

Users define arbitrary intermediaries using the same mechanism:

```nix
den.schema.environment = {};

den.policies.fleet-to-envs = { fleet, ... }:
  map (env: resolve.to "environment" { environment = { name = env; }; })
    [ "prod" "dev" ];

den.policies.env-to-hosts = { environment, ... }:
  lib.concatMap (system:
    map (hostName:
      let host = den.hosts.${system}.${hostName}; in
      lib.optionals (host.environment or null == environment.name) [
        (resolve.to "host" { inherit host; })
        (den.lib.policy.instantiate host)
      ]
    ) (builtins.attrNames (den.hosts.${system} or {}))
  ) (builtins.attrNames (den.hosts or {}));

den.schema.fleet.includes = [ den.policies.fleet-to-envs ];
den.schema.environment.includes = [ den.policies.env-to-hosts ];
```

Scope tree:
```
fleet
├── environment:prod
│   ├── host:igloo
│   └── host:iceberg
├── environment:dev
│   └── host:snowflake
```

`pipe.collect ({ host, ... }: true)` at host scope sees same-environment peers only. The scope tree encodes the topology.

### Three tiers of cost

- **No pipes at all** — zero overhead. `assemblePipes` short-circuits on `pipeNames == []`.
- **Local-scope pipes only** (filter, transform, to, expose) — `assemblePipes` runs per-scope using local `scopedClassImports`. No collect, no sibling iteration.
- **`pipe.collect`** — iterates sibling scopes in the walk. Cost proportional to number of siblings, not total hosts.

## Files changed

| File | Change |
|------|--------|
| `modules/options.nix` | Add `fleet = {};` to schema defaults |
| `modules/policies/flake.nix` | `to-os-outputs` and `to-hm-outputs` emit `resolve.to` + `instantiate` |
| `nix/lib/aspects/fx/resolve.nix` | Delete `mkGlobalPipePool`. `applyInstantiates` reads from `perScope` |
| `nix/lib/aspects/fx/assemble-pipes.nix` | Remove `globalPipePool` param. `collectFromPeers` uses sibling scopes via `scopeParent` |

**Deleted:** `mkGlobalPipePool`, `globalPipePool` parameter threading, per-host `fxResolve` path in `applyInstantiates`.

**Added:** `fleet = {};` schema entry (1 line), sibling-based `collectFromPeers` (~15 lines), `perScope`-reading `applyInstantiates`.

## Testing — blast radius

Eliminating per-host `fxResolve` changes the resolution path for every host. All 742 existing tests must pass. Critical scenarios to verify:

- Host-with-users fan-out works from the single walk (host-to-users policy fires correctly within the unified walk)
- `applyInstantiates` correctly reads from `perScope` (host modules reach `evalModules`)
- Pipe data reaches class modules through augmented scope contexts (firewall aggregation, secrets targeting)
- `pipe.collect` sees sibling hosts (cross-host test)
- `pipe.collect` does NOT see child/parent scopes (entity kind filter)
- `pipe.expose` still works (user → host exposure)
- All existing policy tests pass (routes, provides, excludes, constraints)
- Parametric aspects resolve correctly in the unified walk
- Diamond dependency dedup still works across host scopes

## What NOT to change

- `pipe.collect` predicate API — same `({ host, ... }: expr)` pattern
- `assemblePipes` output shape — still augments `scopeContexts` with pipe data
- `pipe.expose`, `pipe.to`, transform stages — unchanged, use walk's own state
- `policy.instantiate`, `policy.resolve.to` — existing effect types, unchanged
- `modules/outputs.nix` — flake output generation stays as-is
