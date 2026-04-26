# Pipeline Simplification: Provides Removal + Sub-Pipeline + Fan-Out

**Date:** 2026-04-26
**Branch:** feat/traits
**Status:** Approved
**Prerequisites:** Direct-ref policy aspects (Tasks 0, 3, 6 complete; Tasks 1/2/4/5 folded into this spec)

## Context

The direct-ref-aspects implementation revealed that the deferred entityIncludes migration (Tasks 1, 2, 4, 5) is structurally coupled with the pipeline simplification spec's Target 1 (provides removal). Both need entityIncludes/entityProvides gone, both remove rootIncludes. This spec folds them together with Targets 3 (sub-pipeline extraction) and 5 (generalize flake fan-out) into a single plan.

### Already complete (from direct-ref-aspects)

- `policy.aspects` typed as `providerType` with `coercedTo` string→ref migration
- `resolveEntityHandler` always returns valid entity (tombstone path removed)
- All `policy.aspects` switched from string names to direct `den.aspects` refs
- ctx-seen uses path-identity tracking with `aspectValues`

## Scope

Three targets from the pipeline simplification spec:

| Target | Impact | Description |
|--------|--------|-------------|
| **1. Provides removal** | ~155 lines, ~13 branches | Delete entityIncludes/entityProvides, self-provide machinery, cross-provide machinery, rootIncludes |
| **3. Sub-pipeline extraction** | ~30 lines dedup | Thin `runSubPipeline` combinator for three call sites |
| **5. Generalize flake fan-out** | ~27 lines | Replace `targetClass == "flake"` hardcode with `policy.isolateFanOut` |

Targets 2 (collision detection), 4 (classifyKeys), 6 (child shapes) are out of scope.

## Design

### Target 1: Entity Migration + Provides Removal

The coordinated migration has seven steps that must execute in dependency order. Each step tests green independently.

#### Step 1: Move self-provide functions into resolveEntity

`resolveEntity` currently reads `entityIncludes` and `entityProvides` from the module system. Self-provides are delivered by external module files (`modules/context/host.nix`, `user.nix`, etc.).

Move the self-provide functions directly into resolveEntity's `includes` output using the same parametric function pattern the modules use:

```nix
# For host: ({ host }: host.aspect)
# For user: ({ host, user }: user.aspect)
# For home: ({ home }: home.aspect)
# For default: den.default (raw value)
```

The functions are hardcoded in resolveEntity based on entity kind and context shape. This is approach B from the design discussion — if identity/ordering issues arise, fall back to approach C (a new `"emit-self"` effect).

Delete `modules/context/host.nix`, `modules/context/user.nix`. Remove self-provide entries from `modules/aspects/defaults.nix` and `modules/aspects/provides/home-manager.nix`.

After this step, `emitSelfProvide` in `resolveChildren` becomes a functional no-op — no entity has `provides.${name}` set, so the `if provides ? ${name}` check always returns false. The function is structurally deleted later in Step 6 as part of the provides machinery cleanup.

#### Step 2: Move framework aspects to policy.aspects

Framework aspects currently delivered via entityIncludes:

| Source | entityIncludes entry | Migration target |
|--------|---------------------|-----------------|
| `os-class.nix` | `entityIncludes.host = [ host-os-fwd ]` | resolveEntity includes for host entities |
| `os-class.nix` | `entityIncludes.user = [ user-os-fwd ]` | `policy.aspects` on `host-to-hm-users` (and any other host→user policy) |
| `os-user.nix` | `entityIncludes.user = [ fwd ]` | `policy.aspects` on `host-to-hm-users` |
| `wsl.nix` | `entityIncludes."wsl-host" = [ ... ]` | `policy.aspects` on `host-to-wsl-host` |

Host-level `host-os-fwd` has no inbound policy (hosts are root entities). It goes directly into resolveEntity's includes for host entities.

User-level aspects (`user-os-fwd`, os-user `fwd`) go onto the host→user policies. These policies already carry `hostModule` and `userForward` aspects from `makeHomeEnv` — add the framework forwarding aspects to the same list.

Register `den.aspects` entries for `host-os-fwd`, `user-os-fwd`, and os-user `fwd` so they can be referenced as direct refs in `policy.aspects`.

#### Step 3: Delete entityIncludes/entityProvides infrastructure

- Delete `nix/nixModule/entities.nix`
- Remove import from `nix/nixModule/default.nix`
- Update `modules/options.nix`: derive `knownKinds` from `den.schema` instead of `entityIncludes`
- Update `modules/context/has-aspect.nix`: error message references `den.schema` not `entityIncludes`
- Update `modules/compat/ctx-shim.nix`: forward `den.ctx.*` to `den.aspects` with deprecation warning (not to `entityIncludes`)
- Remove existence registration entries: `hmConfigurations.nix` (`flake-hm = []`), `osConfigurations.nix` (`flake-os = []`)
- Update `flakeSystemOutputs.nix`: remove entityIncludes reads, unconditional entity resolution
- Remove `entityIncludes` and `entityProvides` references from resolveEntity

#### Step 4: Remove rootIncludes

- Remove `"rootIncludes"` from `structuralKeysSet` in `aspect.nix`
- Remove rootIncludes phase from `resolveChildren`:
  - Before: `selfProvide → rootIncludes → transitions → includes`
  - After: `selfProvide → transitions → includes`
- Remove `rootIncludes` field from resolveEntity output

#### Step 5: Add provides deprecation shim

In `aspectType` merge (or `aspectContentType`), intercept `provides.X` keys and rewrite them to direct nesting as sub-aspects at key `X`. Emit a trace warning:

```
den: aspect '<name>' uses 'provides.X' — migrate to direct nesting at key 'X'
```

This preserves the user-facing API (`den.aspects.igloo.provides.to-users = { ... }`) while removing all pipeline dependency on the `provides` structural key. The shim operates at the type system level, before the pipeline sees the aspect.

The existing trace warning in `resolveChildren` that fires on `provides` keys can be removed since the shim handles it earlier.

#### Step 6: Delete provides pipeline machinery

- Remove `emitSelfProvide` from `resolveChildren` — ordering becomes: `transitions → includes`
- Remove `emitSelfProvide`, `mkPositionalInclude`, `mkNamedInclude` from `aspect.nix`
- Remove `emitCrossProvider`, `crossProvider` variable, `emitCross` from `resolveTransition` in `transition.nix`
- Remove `provides` from `structuralKeysSet`
- Update `den-brackets.nix` if it encodes the `provides.` naming convention

#### Step 7: Migrate test files

Convert all test files that reference entityIncludes, entityProvides, or use the `provides.X` pattern:

- `den.entityIncludes.X = [ fn ]` where fn is self-provide → delete (resolveEntity handles it)
- `den.entityIncludes.X = [ fwd ]` where fwd is framework → `policy.aspects = [ fwd ]` on relevant policy
- `den.entityIncludes.X = []` (existence registration) → delete entirely
- `den.aspects.*.provides.X = { ... }` → `den.aspects.*.X = { ... }` (direct nesting)
- `den.entityProvides` references → delete

Affected: ~45 files under `templates/ci/modules/features/`, ~6 files under `templates/{default,noflake,...}/`, plus `templates/flake-parts-modules/modules/den.nix` and `templates/flake-parts-modules/modules/perSystem-forward.nix` (flake-parts integration — verify these are in the CI matrix).

### Target 3: Sub-Pipeline Extraction

Extract a thin `runSubPipeline` combinator into `pipeline.nix`:

```nix
# runSubPipeline :: { class, self, ctx } → { imports, traits, provideTo }
runSubPipeline = spec:
  let
    result = fxFullResolve spec;
  in
  {
    imports = result.state.imports null;
    traits = result.state.traits null;
    provideTo = result.state.provideTo or (_: []);
  };
```

Takes the same spec as `fxFullResolve`, runs it, materializes state thunks, returns a plain record. No effects, no state splicing — just data out.

Three call sites updated:

| Site | Post-processing (unchanged) |
|------|---------------------------|
| `resolveFanOut` | Splices `result.imports` into parent via `state.modify` |
| `resolveSiblingTransition` | Sends `provide-to` with `result.traits` |
| `forwardHandler` | Wraps `result.imports` in adapter aspect, splices `result.provideTo` |

Export as `den.lib.aspects.fx.pipeline.runSubPipeline`.

### Target 5: Generalize Flake Fan-Out

Add `isolateFanOut` option to `policy-types.nix`:

```nix
isolateFanOut = lib.mkOption {
  type = lib.types.bool;
  default = false;
  description = "Run each fan-out context in an isolated sub-pipeline.";
};
```

Update `resolveTransition` in `transition.nix`:

```nix
# Before:
if isFanOut && targetClass == "flake" then resolveFanOut ...

# After:
if isFanOut && (transition.routing.isolateFanOut or false) then resolveFanOut ...
```

Set `isolateFanOut = true` on flake system output policies in `modules/policies/flake.nix`.

The `isolateFanOut` value flows from the policy option through the policy dispatch handler, which copies all policy fields into the `routing` record on the dispatch result. `resolveTransition` reads it as `transition.routing.isolateFanOut`.

Remove `targetClass` parameter from `resolveFanOut` — it was only used for the flake class check.

## Dependency Graph

```
Step 1 (self-provides into resolveEntity)
  ↓
Step 2 (framework aspects to policy.aspects)
  ↓
Step 3 (delete entityIncludes/entityProvides infrastructure)
  ↓
Step 4 (remove rootIncludes)
  ↓
Step 5 (provides deprecation shim)
  ↓
Step 6 (delete provides pipeline machinery)
  ↓
Step 7 (migrate test files) — can partially overlap with steps 5-6
  ↓
Target 3 (sub-pipeline extraction) — independent of steps 1-7, but cleaner after
  ↓
Target 5 (generalize flake fan-out) — depends on Target 3
```

Steps 1-4 are the coordinated entity migration. Steps 5-6 are the provides removal. Step 7 spans both. Targets 3 and 5 are independent cleanups that benefit from the simplified pipeline.

## Risks

- **Self-provide identity issues** (Step 1): We hit these during direct-ref-aspects. Approach B (hardcoded parametric functions) avoids the wrapper format issues we encountered. Fallback: approach C (emit-self effect).
- **Host-level framework aspects** (Step 2): `host-os-fwd` has no inbound policy. Goes into resolveEntity includes — acceptable coupling since it's a framework concern.
- **provides shim correctness** (Step 5): The shim rewrites at the type level. Cross-provides with `provides.to-users` where the target is a different entity kind need the rewrite to produce the correct sub-aspect structure. The `mutual-provider` module is the primary consumer — verify its behavior specifically.
- **Test migration volume** (Step 7): ~50+ files. Bulk migration with focused verification.
- **flake-parts templates** (Step 7): `templates/flake-parts-modules/` uses entityIncludes in a different integration pattern. May be outside default CI matrix — verify coverage.

## Nix Conventions

- `nix develop -c just fmt` before committing
- `git -c core.hooksPath=/dev/null commit`
- No Co-Authored-By trailers
- No docs/superpowers/ files committed
- One agent at a time, no parallel execution
- Stage specific files, never `git add -A`
