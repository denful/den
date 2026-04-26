# Provides Removal: Complete the Pipeline Simplification

**Date:** 2026-04-26
**Branch:** feat/traits
**Status:** Draft
**Prerequisites:** Pipeline simplification (complete — entityIncludes deleted, rootIncludes removed, runSubPipeline extracted, isolateFanOut landed)

## Context

The pipeline simplification plan completed the entity migration (entityIncludes → `den.schema.X.includes`) and infrastructure cleanup (rootIncludes removal, sub-pipeline combinator, isolateFanOut). However, the `provides` API removal was deferred because `provides.X` patterns are still actively used in ~111 template occurrences and the `mutual-provider` framework module.

This spec covers the remaining work: migrating all `provides.X` patterns to direct nesting, then deleting the pipeline machinery that serves them.

### What was completed

| Item | Status |
|------|--------|
| entityIncludes/entityProvides deleted | Done |
| Self-provides in resolveEntity | Done — `__fn`/`__args` wrapper, schema-based detection |
| Framework aspects on policy.aspects | Done — os-class, os-user, wsl |
| rootIncludes phase removed | Done — includes resolve before transitions now |
| `den.schema.X.includes` surface | Done — replaces entityIncludes |
| runSubPipeline combinator | Done |
| policy.isolateFanOut | Done |
| Provides deprecation at lookup layer | Done — den-brackets.nix fallback |

### What remains

| Item | Lines | Impact |
|------|-------|--------|
| Migrate `provides.X` patterns in templates | ~111 occurrences, ~35 files | User API change |
| Migrate `mutual-provider` module | ~15 lines | Framework module reads `aspect.provides.*` |
| Delete `emitSelfProvide` | ~55 lines | Pipeline simplification |
| Delete `mkPositionalInclude` + `mkNamedInclude` | ~60 lines | Pipeline simplification |
| Delete `emitCrossProvider` | ~45 lines | Pipeline simplification |
| Remove `crossProvider`/`emitCross` from `resolveTransition` | ~10 lines | Pipeline simplification |
| Remove `provides` from `structuralKeysSet` | 1 line | Structural key cleanup |
| Remove `provides` option from `aspectSubmodule` | ~15 lines | Type system cleanup |
| Remove `_` alias for `provides` | 1 line | Type system cleanup |
| Clean up den-brackets.nix provides fallback | ~20 lines | Lookup layer cleanup |

## Design

### 1. Migrate `provides.X` to direct nesting

The `provides` submodule on aspects acts as a namespace for cross-entity data and named sub-aspects. With direct nesting, these become top-level keys on the aspect:

```nix
# Before:
den.aspects.igloo.provides.to-users = { homeManager.programs.direnv.enable = true; };
den.aspects.igloo.provides.alice = { homeManager.programs.vim.enable = true; };

# After:
den.aspects.igloo.to-users = { homeManager.programs.direnv.enable = true; };
den.aspects.igloo.alice = { homeManager.programs.vim.enable = true; };
```

This is safe because the aspect's freeformType (`lazyAttrsOf aspectContentType`) already accepts arbitrary keys. The `provides` submodule was always a namespace choice, not a structural requirement.

**Pattern inventory** (from grep of templates/):

| Pattern | Count | Migration |
|---------|-------|-----------|
| `provides.to-users = { ... }` | ~21 | Direct nesting: `to-users = { ... }` |
| `provides.to-hosts = { ... }` | ~4 | Direct nesting: `to-hosts = { ... }` |
| `provides.${specific-name} = { ... }` | ~40 | Direct nesting: `${name} = { ... }` |
| `provides.X` via bracket syntax `<igloo/to-users>` | ~15 | Already handled by den-brackets.nix fallback |
| `aspect.provides.X` programmatic reads | ~30 | Must update `mutual-provider` and any test that reads `.provides.X` |

**Total**: ~246 occurrences across ~76 files (including all patterns, not just `provides.X` writes).

### 2. Migrate `mutual-provider` module

`mutual-provider` (`modules/aspects/provides/mutual-provider.nix`) reads cross-entity data via `aspect.provides.*`:

```nix
find-mutual = from: to: from.aspect.provides.${to.aspect.name} or { };
to-hosts = from: from.aspect.provides.to-hosts or { };
to-users = from: from.aspect.provides.to-users or { };
```

And for standalone homes:
```nix
prov = home.aspect.provides.${home.hostName} or null;
```

After migration, these read directly from the aspect:

```nix
find-mutual = from: to: from.aspect.${to.aspect.name} or { };
to-hosts = from: from.aspect.to-hosts or { };
to-users = from: from.aspect.to-users or { };
```

And:
```nix
prov = home.aspect.${home.hostName} or null;
```

**Risk:** Direct reads from `aspect.X` will also see structural keys (`name`, `meta`, `includes`, etc.) and class keys (`nixos`, `homeManager`, etc.). The `find-mutual` lookup uses `to.aspect.name` (the target aspect's name, e.g., "igloo") as the key. If the target's name collides with a structural or class key, the lookup would return the wrong value.

**Mitigation:** The `provides` namespace prevented this collision. With direct nesting, the only collision risk is if an aspect has `name = "nixos"` and another aspect does `find-mutual` targeting it — `aspect.nixos` would be the NixOS class content, not the cross-provide. In practice, aspect names don't collide with class names (aspects are named after entities like "igloo", "tux", not after classes). Add a guard in `find-mutual` that skips structural/class keys:

```nix
find-mutual = from: to:
  let key = to.aspect.name; in
  if structuralKeys ? ${key} || classRegistry ? ${key} then {}
  else from.aspect.${key} or {};
```

Or accept the collision risk as extremely low and document it.

**Parametric cross-provides classification:** When `provides.to-users` is a function (e.g., `{ user, ... }: { homeManager... }`), moving it to direct `to-users` means `classifyKeys` receives an `aspectContentType`-wrapped function value. The depth probe cannot see through functions to detect class sub-keys, so the key is classified as `unregisteredClassKey` (with trace warning). This still works at runtime — unregistered class keys go through the `compileStatic` class-key path — but produces user-facing trace noise. Options:

1. Suppress the trace warning for keys that were migrated from `provides` (add to a known-cross-provide set)
2. Accept the noise during transition; it goes away when Target 4 (classifyKeys → declared schemas) lands
3. Migrate function-valued cross-provides to use `includes` instead of direct nesting (wrapping in `{ includes = [fn]; }`)

Option 2 is pragmatic — the noise is transient and Target 4 eliminates `classifyKeys` entirely.

**Note on `den.provides.*`:** The `den.provides` namespace (`den.provides.mutual-provider`, `den.provides.forward`, etc.) is the provider factory registry — NOT the aspect-level `provides` sub-key. The factory namespace is unaffected by this migration and is out of scope.

### 3. Delete `emitSelfProvide` and helpers

After all `provides.X` patterns are migrated to direct nesting:

- No aspect has `provides.${name}` set (self-provides are in resolveEntity)
- No aspect has `provides.otherName` set (cross-provides are direct nested keys)
- `emitSelfProvide` always returns `fx.pure []` (the `provides ? ${name}` check is always false)

Delete from `aspect.nix`:
- `emitSelfProvide` (~lines 573-623)
- `mkPositionalInclude` (~lines 512-541)
- `mkNamedInclude` (~lines 543-571)

Update `resolveChildren`:
```nix
# Before:
childResolution = fx.bind (builtins.seq _ (emitSelfProvide aspect)) (
  selfProvResults:
  fx.bind (emitIncludes emitCtx (aspect.includes or [])) (
    children:
    fx.bind (emitTransitions aspect) (
      transitionResults:
      fx.pure (selfProvResults ++ children ++ transitionResults)

# After:
childResolution = fx.bind (emitIncludes emitCtx (aspect.includes or [])) (
  children:
  fx.bind (emitTransitions aspect) (
    transitionResults:
    fx.pure (children ++ transitionResults)
```

Also remove the `providesKeys` trace warning block — no longer needed.

### 4. Delete `emitCrossProvider` and `crossProvider`

In `transition.nix`:
- Delete `emitCrossProvider` function (~lines 125-167)
- In `resolveTransition`, remove:
  ```nix
  sourceProvides = sourceAspect.provides or { };
  crossProvider = sourceProvides.${targetKey} or null;
  emitCross = emitCrossProvider { inherit crossProvider sourceAspect targetKey; };
  ```
- Replace `emitCross` call with direct result passthrough

### 5. Remove `provides` from type system

In `nix/lib/aspects/types.nix`:
- Remove the `provides` option from `aspectSubmodule` (lines 308-322)
- Remove the `_` alias: `(lib.mkAliasOptionModule [ "_" ] [ "provides" ])` (line 231)

### 6. Remove `provides` from structuralKeysSet

In `nix/lib/aspects/fx/aspect.nix` line 17, remove `"provides"`.

After this, `classifyKeys` will not encounter `provides` as a key since the option is gone. Any aspect that still had `provides` set would get it classified as a freeform nested key — which is the desired behavior (direct nesting).

### 7. Clean up den-brackets.nix

Remove `resolveWithProvidesFallback` — the fallback to `provides` is no longer needed since provides doesn't exist. Direct resolution only:

```nix
findAspect = path:
  let
    head = lib.head path;
    tail = lib.tail path;
  in
  if head == "den" then
    lib.getAttrFromPath (["den"] ++ tail) config
  else if builtins.hasAttr head config.den.aspects then
    lib.getAttrFromPath (["den" "aspects"] ++ path) config
  else if lib.hasAttrByPath ["ful" head] config.den then
    lib.getAttrFromPath (["den" "ful"] ++ path) config
  else
    throw "Aspect not found: ${lib.concatStringsSep "." path}";
```

## Dependency Graph

```
Step 1 (migrate provides.X in templates) — the bulk migration
  ↓
Step 2 (migrate mutual-provider reads)
  ↓
Step 3 (delete emitSelfProvide + helpers)
Step 4 (delete emitCrossProvider + crossProvider) — independent of Step 3
  ↓
Step 5 (remove provides option + _ alias)
  ↓
Step 6 (remove provides from structuralKeysSet)
  ↓
Step 7 (clean up den-brackets.nix)
```

Steps 1-2 are the migration. Steps 3-4 (delete pipeline machinery) depend on 1-2. Step 5 (remove option) depends on 3-4. Step 6 (structuralKeysSet) depends on 5. Step 7 depends on 6.

## Risks

- **Name collision in direct nesting** (Step 2): If an aspect name matches a class name (e.g., `nixos`), `find-mutual` would return class content instead of cross-provide data. Extremely unlikely in practice — add a guard or document.
- **Downstream consumers** (Step 1): Any den user with `provides.X` patterns in their config needs to migrate. The trace warning from den-brackets.nix has been live — users have been warned.
- **`_` alias removal** (Step 5): Users may use `den.aspects.igloo._.to-users` as shorthand. This breaks. The `_` key becomes a freeform key on the aspect instead of an alias for provides.
- **Template migration volume** (Step 1): ~111 occurrences across ~35 files. Mechanical but high volume.

## Out of Scope

These remain from the original pipeline-simplification-targets spec:
- **Target 2:** Remove `wrapClassModule` collision detection (~100-110 lines) — breaking change, needs namespacing
- **Target 4:** Replace `classifyKeys` with declared schemas (~67 lines) — should follow provides removal
- **Target 6:** Normalize child shapes at source (~57 lines) — depends on Target 2
