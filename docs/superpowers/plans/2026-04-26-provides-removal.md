# Provides Removal Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate all `provides.X` patterns to direct nesting, then delete the provides pipeline machinery (emitSelfProvide, emitCrossProvider, mkPositionalInclude, mkNamedInclude), the provides option, and the `_` alias.

**Architecture:** `den.aspects.igloo.provides.to-users = { ... }` becomes `den.aspects.igloo.to-users = { ... }`. The `mutual-provider` module reads directly from aspect keys instead of `aspect.provides.*`. Pipeline functions that handled provides are deleted. The `provides` option and `_` alias are removed from `aspectSubmodule`.

**Tech Stack:** Nix module system, nix-effects, nix-unit tests

**Spec:** `docs/superpowers/specs/2026-04-26-provides-removal-design.md`

---

## File Structure

### Major modifications
| File | Changes |
|------|---------|
| `modules/aspects/provides/mutual-provider.nix` | Read from `aspect.X` instead of `aspect.provides.X` |
| `nix/lib/aspects/fx/aspect.nix` | Delete emitSelfProvide, mkPositionalInclude, mkNamedInclude; remove provides from structuralKeysSet; simplify resolveChildren |
| `nix/lib/aspects/fx/handlers/transition.nix` | Delete emitCrossProvider; remove crossProvider/emitCross from resolveTransition |
| `nix/lib/aspects/types.nix` | Remove provides option and `_` alias from aspectSubmodule |
| `nix/lib/den-brackets.nix` | Remove resolveWithProvidesFallback; simplify to direct resolution |
| ~76 files under `templates/` | Migrate `provides.X` to direct nesting |

---

## Task 0: Migrate provides.X patterns in templates AND mutual-provider reads

**Goal:** Convert all `aspect.provides.X = value` writes to direct nesting `aspect.X = value` AND update `mutual-provider` reads — in a single atomic commit to avoid test breakage.

**Files:**
- Modify: ~76 files under `templates/ci/modules/features/`, `templates/default/`, `templates/ci/provider/`
- Modify: `modules/aspects/provides/mutual-provider.nix` (reads from aspect.provides.*)
- Test: 632/632 tests pass

**CRITICAL:** Template writes and mutual-provider reads MUST be migrated in the same commit. If writes move to direct nesting but mutual-provider still reads from `aspect.provides.X`, all mutual-provider tests (~30 tests) will fail.

**Acceptance Criteria:**
- [ ] No template file writes to `den.aspects.*.provides.*` (except through `den.provides.*` factory namespace)
- [ ] No template file reads `*.aspect.provides.*`
- [ ] `mutual-provider` reads from `aspect.X` not `aspect.provides.X`
- [ ] 632/632 tests pass

**Verify:** `nix develop -c just fmt && just ci`

**Steps:**

- [ ] **Step 1: Find all provides.X writes**

```bash
grep -rn "\.provides\." templates/ --include="*.nix" | grep -v "den\.provides\."
```

This finds all `provides.X` usages EXCLUDING the `den.provides.*` factory namespace (which is unrelated).

- [ ] **Step 2: Mechanical bulk migration**

The migration is purely mechanical for writes:
```nix
# Before:
den.aspects.igloo.provides.to-users = { homeManager.programs.direnv.enable = true; };
# After:
den.aspects.igloo.to-users = { homeManager.programs.direnv.enable = true; };
```

For each file, remove `.provides` from the path. The aspect's freeformType accepts these keys.

**Watch for:** Files that read `provides.X` (not just write), e.g.:
```nix
# Before:
den.aspects.igloo.includes = [ den.aspects.foo.provides.sub ];
# After:
den.aspects.igloo.includes = [ den.aspects.foo.sub ];
```

- [ ] **Step 3: Migrate namespace provides**

Namespace aspects use `provides` too:
```nix
# Before:
ns.root.provides.branch.provides.leaf.nixos.truth = true;
# After:
ns.root.branch.leaf.nixos.truth = true;
```

- [ ] **Step 4: Migrate provider template provides**

`templates/ci/provider/modules/den.nix` uses `provider.*.provides.*`:
```nix
# Before:
provider.tools.provides.dev.provides.editors = { ... };
# After:
provider.tools.dev.editors = { ... };
```

- [ ] **Step 5: Verify no provides.X patterns remain**

```bash
grep -rn "\.provides\." templates/ --include="*.nix" | grep -v "den\.provides\."
```

Should return zero matches.

- [ ] **Step 6: Migrate mutual-provider reads (SAME COMMIT)**

At `modules/aspects/provides/mutual-provider.nix` lines 36-38:
```nix
# Before:
find-mutual = from: to: from.aspect.provides.${to.aspect.name} or { };
to-hosts = from: from.aspect.provides.to-hosts or { };
to-users = from: from.aspect.provides.to-users or { };

# After:
find-mutual = from: to: from.aspect.${to.aspect.name} or { };
to-hosts = from: from.aspect.to-hosts or { };
to-users = from: from.aspect.to-users or { };
```

At line 74:
```nix
# Before:
prov = home.aspect.provides.${home.hostName} or null;

# After:
prov = home.aspect.${home.hostName} or null;
```

Also update the module's description string (lines 6-33) to show direct nesting instead of `provides.X`.

- [ ] **Step 7: Format, test, commit (all changes together)**

```bash
nix develop -c just fmt && just ci
git add templates/ modules/aspects/provides/mutual-provider.nix
git -c core.hooksPath=/dev/null commit -m "refactor: migrate all provides.X to direct nesting"
```

---

## Task 1: Delete provides pipeline machinery

**Goal:** Delete emitSelfProvide, mkPositionalInclude, mkNamedInclude, emitCrossProvider, crossProvider. Simplify resolveChildren. Also remove `provides` propagation in aspectToEffect.

**Files:**
- Modify: `nix/lib/aspects/fx/aspect.nix`
- Modify: `nix/lib/aspects/fx/handlers/transition.nix`
- Test: 632/632 tests pass

**Acceptance Criteria:**
- [ ] `emitSelfProvide`, `mkPositionalInclude`, `mkNamedInclude` deleted from aspect.nix
- [ ] `emitCrossProvider` deleted from transition.nix
- [ ] `crossProvider`/`emitCross` removed from resolveTransition
- [ ] `resolveChildren` ordering: includes → transitions (no emitSelfProvide)
- [ ] `providesKeys` trace warning removed from resolveChildren
- [ ] `provides` propagation in `aspectToEffect` removed (line ~833: `lib.optionalAttrs (aspect ? provides)`)
- [ ] 632/632 tests pass

**Verify:** `nix develop -c just fmt && just ci`

**Steps:**

- [ ] **Step 1: Delete emitSelfProvide + helpers from aspect.nix**

Delete these functions:
- `mkPositionalInclude` (~lines 512-541)
- `mkNamedInclude` (~lines 543-571)
- `emitSelfProvide` (~lines 573-623)

Remove them from the export block at the bottom of the file.

- [ ] **Step 2: Simplify resolveChildren in aspect.nix**

Remove the `emitSelfProvide` call and the `providesKeys` trace warning:

```nix
# Before:
providesKeys = builtins.filter (k: k != aspectName) (builtins.attrNames (aspect.provides or { }));
_ = if providesKeys != [ ] then builtins.trace "..." null else null;
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

- [ ] **Step 3: Delete emitCrossProvider from transition.nix**

Delete the `emitCrossProvider` function (~lines 125-167).

- [ ] **Step 4: Remove crossProvider from resolveTransition**

Remove these lines:
```nix
sourceProvides = sourceAspect.provides or { };
crossProvider = sourceProvides.${targetKey} or null;
emitCross = emitCrossProvider { inherit crossProvider sourceAspect targetKey; };
```

And replace the `emitCross` bind:
```nix
# Before:
_: fx.bind withTarget (targetResults: emitCross scopedCtx scopeHandlers ctxNames targetResults)

# After:
_: withTarget
```

- [ ] **Step 5: Remove provides propagation from aspectToEffect**

In `aspect.nix`, in the `aspectToEffect` parametric resolution path (~line 833):
```nix
# Remove this line:
// lib.optionalAttrs (aspect ? provides) { inherit (aspect) provides; };
```

This propagated `provides` through parametric resolution — dead code after provides removal.

- [ ] **Step 6: Format, test, commit**

```bash
nix develop -c just fmt && just ci
git add nix/lib/aspects/fx/aspect.nix nix/lib/aspects/fx/handlers/transition.nix
git -c core.hooksPath=/dev/null commit -m "refactor: delete emitSelfProvide, emitCrossProvider, provides pipeline machinery"
```

---

## Task 2: Remove provides option and clean up

**Goal:** Delete the `provides` option from aspectSubmodule, remove the `_` alias, remove `provides` from structuralKeysSet, clean up den-brackets.nix.

**Files:**
- Modify: `nix/lib/aspects/types.nix`
- Modify: `nix/lib/aspects/fx/aspect.nix`
- Modify: `nix/lib/den-brackets.nix`
- Test: 632/632 tests pass

**Acceptance Criteria:**
- [ ] `provides` option removed from aspectSubmodule
- [ ] `_` alias removed
- [ ] `provides` removed from structuralKeysSet
- [ ] den-brackets.nix no longer has provides fallback
- [ ] 632/632 tests pass

**Verify:** `nix develop -c just fmt && just ci`

**Steps:**

- [ ] **Step 1: Remove provides option from types.nix**

At `nix/lib/aspects/types.nix` lines 308-322, delete the `provides` option.

At line 231, delete the `_` alias:
```nix
(lib.mkAliasOptionModule [ "_" ] [ "provides" ])
```

- [ ] **Step 2: Remove provides and _ from structuralKeysSet**

At `nix/lib/aspects/fx/aspect.nix`, remove both `"provides"` and `"_"` from `structuralKeysSet`. The `_` was the alias for provides — with both gone, neither should be structural.

- [ ] **Step 3: Clean up den-brackets.nix**

Remove `resolveWithProvidesFallback` and simplify `findAspect` to direct resolution. **IMPORTANT:** Preserve the `isProvider` branch that handles `<den/mutual-provider>` syntax — this resolves `den.provides.*` (the factory namespace), which is unrelated to the aspect-level provides we're removing.

```nix
findAspect = path:
  let
    head = lib.head path;
    tail = lib.tail path;
  in
  if head == "den" then
    let
      # <den/mutual-provider> → config.den.provides.mutual-provider
      firstTail = if tail != [] then lib.head tail else null;
      isProvider = firstTail != null && builtins.hasAttr firstTail config.den.provides;
    in
    if isProvider then
      lib.getAttrFromPath (["den" "provides"] ++ lib.tail (lib.tail path)) config
    else
      lib.getAttrFromPath (["den"] ++ tail) config
  else if builtins.hasAttr head config.den.aspects then
    lib.getAttrFromPath (["den" "aspects"] ++ path) config
  else if lib.hasAttrByPath ["ful" head] config.den then
    lib.getAttrFromPath (["den" "ful"] ++ path) config
  else
    throw "Aspect not found: ${lib.concatStringsSep "." path}";
```

- [ ] **Step 4: Format, test, commit**

```bash
nix develop -c just fmt && just ci
git add nix/lib/aspects/types.nix nix/lib/aspects/fx/aspect.nix nix/lib/den-brackets.nix
git -c core.hooksPath=/dev/null commit -m "feat: remove provides option, _ alias, structuralKeysSet entry"
```

---

## Dependency Graph

```
Task 0 (migrate provides.X in templates + mutual-provider reads — single atomic commit)
  ↓
Task 1 (delete pipeline machinery) ← depends on Task 0
  ↓
Task 2 (remove provides option + cleanup) ← depends on Task 1
```

Linear chain — each task depends on the previous. 3 tasks, 3 commits.

---

## Notes for Implementers

### Migration pattern
```nix
# Write migration:
den.aspects.igloo.provides.to-users = { ... };
→ den.aspects.igloo.to-users = { ... };

# Read migration:
den.aspects.foo.provides.sub
→ den.aspects.foo.sub

# Namespace migration:
ns.root.provides.branch.provides.leaf
→ ns.root.branch.leaf

# Include ref migration:
den.aspects.igloo.includes = [ den.aspects.foo.provides.sub ];
→ den.aspects.igloo.includes = [ den.aspects.foo.sub ];
```

### What NOT to migrate
- `den.provides.*` (factory namespace — `den.provides.forward`, `den.provides.mutual-provider`, etc.) — this is a DIFFERENT `provides`, not the aspect-level one
- Structural keys like `aspect.name`, `aspect.meta`, `aspect.includes` — these aren't provides

### Nix conventions
- `nix develop -c just fmt` before committing
- `git -c core.hooksPath=/dev/null commit`
- Do NOT add Co-Authored-By trailers or commit docs/superpowers/ files
- One agent at a time, no parallel execution
- Stage specific files by name, never `git add -A` or `git add .`

### Test commands
- `just ci` for quick (632 tests), `just ci-deep` for verbose errors
- `just ci-deep <suite>` for focused debugging

### Known issue: parametric cross-provides trace noise
Function-valued cross-provides (e.g., `to-users = { user, ... }: { ... }`) after migration to direct nesting will trigger a `classifyKeys` trace warning about unregistered class keys. This is cosmetic — the code path still works. The warning disappears when Target 4 (classifyKeys → declared schemas) is implemented. Accept the noise for now.
