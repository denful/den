# Pipes and Quirks Implementation Plan

> **STATUS: PARTIALLY COMPLETE — see audit notes below.**
> Tasks 1-7 complete (742/742 tests). Remaining work moved to `2026-05-06-pipes-remaining-work.md`.
> Fleet scope-tree migration in progress: `2026-05-06-fleet-scope-tree-collect.md`.

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the pipes and quirks system — a structured data flow mechanism that lets aspects emit named data (quirks) and consume aggregated data through declared pipes, with policy-mediated cross-scope routing.

**Architecture:** Pipes reuse the existing `scopedClassImports` collection infrastructure. A new `den.quirks` registry (originally `den.pipes`, renamed) distinguishes pipe keys from class keys at classification time. A new `assemblePipes` post-pipeline phase (before `wrapPerScope`) reads pipe entries from `scopedClassImports`, applies policy pipe effects, and injects assembled data into `scopeContexts` for delivery via `wrapClassModule`'s existing `ctx ? ${k}` mechanism.

**Tech Stack:** Nix (NixOS module system, fx algebraic effects pipeline)

**Spec:** `~/Documents/den-specs/design/pipes-and-quirks.md`

---

## Audit Notes (2026-05-06)

| Task | Status | Notes |
|------|--------|-------|
| 1: Pipe Registry | **Done** | `den.pipes` option added (to be renamed `den.quirks`) |
| 2: Key Classification | **Done** | `classifyKeys` returns `pipeKeys` |
| 3: Local Consumption | **Done** | `assemblePipes` + `wrapClassModule` delivery |
| 4: Transform Stages | **Done** | `pipe.from`/filter/transform/fold/append/for |
| 5: pipe.to | **Done** | Aspect targeting, full identity pathkey matching |
| 6: pipe.expose | **Done** | Bottom-up assembly, sibling isolation verified |
| 7: pipe.collect | **Done** | Cross-scope collection via `mkGlobalPipePool` (TEMPORARY) |
| 7b: Fleet migration | **In progress** | Replacing `mkGlobalPipePool` with fleet entity + sibling collect |
| 8: Provenance + Thunks | **Pending** | Moved to `pipes-remaining-work.md` |
| 3b: Discriminator deferral | **Pending** | Moved to `pipes-remaining-work.md` |
| Rename den.pipes → den.quirks | **Pending** | Moved to `pipes-remaining-work.md` |

**Design changes from original plan:**
- `pipe.collect` redesigned: uses sibling scopes via `scopeParent` instead of global pool (spec: `fleet-entity-scope-tree-collect.md`)
- `den.pipes` will be renamed to `den.quirks`
- `pipe.from` will accept schema refs (`pipe.from den.quirks.firewall`) in addition to strings
- Fleet entity is user-defined (not built-in magic), optional grouping for topology control

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `nix/nixModule/pipes.nix` | `options.den.pipes` NixOS option definition |
| `nix/lib/aspects/fx/assemble-pipes.nix` | `assemblePipes` post-pipeline phase — reads pipe entries, applies effects, injects into scope contexts |
| `nix/lib/aspects/fx/handlers/register-pipe-effect.nix` | Handler for `register-pipe-effect` — collects pipe effects into `scopedPipeEffects` |
| `nix/lib/aspects/fx/pipe-builder.nix` | `pipe.*` API — `pipe.from`, `pipe.filter`, `pipe.transform`, `pipe.fold`, `pipe.append`, `pipe.for`, `pipe.to`, `pipe.expose`, `pipe.collect`, `pipe.withProvenance` |
| `templates/ci/modules/features/pipes.nix` | Phase 1-2 tests: registry, classification, local consumption |
| `templates/ci/modules/features/pipe-policy.nix` | Phase 3-4 tests: transform stages, aspect targeting |
| `templates/ci/modules/features/pipe-scope.nix` | Phase 5-7 tests: expose, collect, provenance, config thunks |

### Modified files

| File | Changes |
|------|---------|
| `modules/options.nix` | Add `options.den.pipes` alongside `options.den.classes` |
| `nix/nixModule/default.nix` | Import `./pipes.nix` |
| `nix/lib/aspects/fx/key-classification.nix` | Add `pipeRegistry`, return `pipeKeys` category |
| `nix/lib/aspects/fx/handlers/classify.nix` | Pass `pipeKeys` through (don't merge into classKeys) |
| `nix/lib/aspects/fx/handlers/emit-classes.nix` | Skip class-wrapping for pipe keys (emit raw, no module identity) |
| `nix/lib/aspects/fx/resolve.nix` | Insert `assemblePipes` before `wrapPerScope`, augment scope contexts |
| `nix/lib/aspects/fx/pipeline.nix` | Add `scopedPipeEffects` to `defaultState`, wire `registerPipeEffectHandler` |
| `nix/lib/aspects/fx/handlers/default.nix` | Import and merge `register-pipe-effect.nix` handler |
| `nix/lib/aspects/fx/handlers/bind.nix` | Extend pipe-arg recognition for discriminator deferral |
| `nix/lib/policy-effects.nix` | Add `pipe` namespace with `pipe.from` and stage constructors |
| `nix/lib/aspects/fx/policy/dispatch.nix` | Add `"pipe"` to `validEffectTypes` |
| `nix/lib/aspects/fx/policy/classify.nix` | Add `pipeEffects` extraction |
| `nix/lib/aspects/fx/handlers/emit-policy-effects.nix` | Emit pipe effects via `register-pipe-effect` |
| `nix/lib/aspects/fx/wrap-classes.nix` | Skip wrapping for pipe-key entries (pass through raw) |

---

### Task 1: Pipe Registry and Option Definition

**Goal:** Add `den.pipes` option so users can declare named pipes. No behavioral changes — purely additive.

**Files:**
- Create: `nix/nixModule/pipes.nix`
- Modify: `modules/options.nix:178-210` (add `pipeSchemaType` and `options.den.pipes`)
- Modify: `nix/nixModule/default.nix:4-8` (add import)

**Acceptance Criteria:**
- [ ] `den.pipes.firewall = { description = "..."; }` is accepted without error
- [ ] `den.pipes` has `lazyAttrsOf` type with `description` submodule
- [ ] All 713 existing tests pass unchanged

**Verify:** `nix develop -c just ci` → all pass

**Steps:**

- [ ] **Step 1: Define pipe schema type in `modules/options.nix`**

Add `pipeSchemaType` alongside `classSchemaType` (line ~178) and add the option:

```nix
# In modules/options.nix, after classSchemaType definition (~line 191):
pipeSchemaType = lib.types.submodule (
  { ... }:
  {
    options.description = lib.mkOption {
      description = "Human-readable description of this pipe.";
      type = lib.types.str;
    };
  }
);
```

Add option after `options.den.classes` (~line 210):

```nix
options.den.pipes = lib.mkOption {
  description = "Pipe declarations — named data routes for structured quirk flow";
  type = lib.types.lazyAttrsOf pipeSchemaType;
  default = { };
};
```

- [ ] **Step 2: Create `nix/nixModule/pipes.nix`**

```nix
{ config, lib, ... }:
{
  # den.pipes option is defined in modules/options.nix alongside den.classes.
  # This module handles any pipe-specific config merging from namespace sources.
}
```

Note: The option itself lives in `modules/options.nix` (same pattern as `den.classes`). This nixModule file exists for future namespace pipe merging (same pattern as `namespace.nix` does for classes).

- [ ] **Step 3: Add import to `nix/nixModule/default.nix`**

```nix
# Add ./pipes.nix to the imports list
imports = map (f: import f (args // { den = config.den; })) [
  ./lib.nix
  ./policies.nix
  ./aspects.nix
  ./pipes.nix
];
```

- [ ] **Step 4: Add collision assertion**

In `modules/options.nix`, add an assertion that `den.classes` and `den.pipes` keys don't overlap:

```nix
# In the config section of modules/options.nix:
config.assertions = [
  {
    assertion =
      let
        classNames = builtins.attrNames (config.den.classes or { });
        pipeNames = builtins.attrNames (config.den.pipes or { });
        overlap = builtins.filter (k: builtins.elem k pipeNames) classNames;
      in
      overlap == [ ];
    message = "den: classes and pipes must not share key names. Overlapping: ${builtins.concatStringsSep ", " (
      let
        classNames = builtins.attrNames (config.den.classes or { });
        pipeNames = builtins.attrNames (config.den.pipes or { });
      in
      builtins.filter (k: builtins.elem k pipeNames) classNames
    )}";
  }
];
```

- [ ] **Step 5: Write tests and verify**

Create initial test entries in `templates/ci/modules/features/pipes.nix`:

```nix
{ denTest, lib, ... }:
{
  flake.tests.pipes = {

    # Pipe declaration accepted without error.
    test-pipe-declaration = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.pipes.firewall = { description = "Firewall port declarations"; };
        den.aspects.igloo = {
          nixos.networking.hostName = "pipe-test";
        };
        expr = igloo.networking.hostName;
        expected = "pipe-test";
      }
    );

  };
}
```

Register the test file in the CI suite module list.

```bash
git add nix/nixModule/pipes.nix templates/ci/modules/features/pipes.nix
nix develop -c just fmt
nix develop -c just ci
git commit -c commit.gpgsign=false -m "feat(pipes): add den.pipes option and pipe registry"
```

---

### Task 2: Key Classification — Pipe Keys as Separate Category

**Goal:** `classifyKeys` recognizes pipe keys and returns them separately from class keys. Pipe keys still flow through `emit-class` into `scopedClassImports`, but are not wrapped as class modules by `wrapPerScope`.

**Files:**
- Modify: `nix/lib/aspects/fx/key-classification.nix:30-70`
- Modify: `nix/lib/aspects/fx/handlers/classify.nix:11-24`
- Modify: `nix/lib/aspects/fx/handlers/emit-classes.nix:68-86`
- Modify: `nix/lib/aspects/fx/wrap-classes.nix:155-162`
- Test: `templates/ci/modules/features/pipes.nix`

**Acceptance Criteria:**
- [ ] `classifyKeys` returns `{ classKeys, nestedKeys, unregisteredClassKeys, pipeKeys }`
- [ ] Pipe keys are emitted via `emit-class` (reach `scopedClassImports`)
- [ ] Pipe keys are NOT wrapped as class modules by `wrapCollectedClasses`
- [ ] Existing tests pass unchanged

**Verify:** `nix develop -c just ci` → all pass

**Steps:**

- [ ] **Step 1: Add `pipeRegistry` to `key-classification.nix`**

```nix
# After classRegistry (line 33):
pipeRegistry = den.pipes or { };
```

Update `classifyKeys` (lines 48-70) to add pipe key detection:

```nix
classifyKeys =
  targetClass: aspect:
  let
    allKeys = builtins.filter (k: !(structuralKeysSet ? ${k})) (builtins.attrNames aspect);
  in
  if classRegistry == { } && pipeRegistry == { } then
    {
      classKeys = allKeys;
      nestedKeys = [ ];
      unregisteredClassKeys = [ ];
      pipeKeys = [ ];
    }
  else
    let
      isPipeKey = k: pipeRegistry ? ${k};
      isClassKey = k: classRegistry ? ${k} || (targetClass != null && k == targetClass);
      pipeKeys = builtins.filter isPipeKey allKeys;
      nonPipeKeys = builtins.filter (k: !isPipeKey k) allKeys;
      classKeys = builtins.filter isClassKey nonPipeKeys;
      nonClassKeys = builtins.filter (k: !isClassKey k) nonPipeKeys;
      classified = lib.partition (isNestedKey aspect) nonClassKeys;
    in
    {
      inherit classKeys pipeKeys;
      nestedKeys = classified.right;
      unregisteredClassKeys = classified.wrong;
    };
```

Export `pipeRegistry`:

```nix
{
  inherit structuralKeysSet classifyKeys pipeRegistry;
}
```

- [ ] **Step 2: Update classify handler to pass pipe keys**

In `handlers/classify.nix` (lines 11-24), pass pipe keys alongside class keys:

```nix
classifyHandler = {
  "classify" =
    { param, state }:
    let
      classified = classifyKeys param.targetClass param.aspect;
    in
    {
      resume = {
        classKeys = classified.classKeys ++ classified.unregisteredClassKeys;
        inherit (classified) nestedKeys pipeKeys;
      };
      inherit state;
    };
};
```

- [ ] **Step 3: Update emit-classes handler to emit pipe keys**

In `handlers/emit-classes.nix`, the `emit-classes` effect handler currently receives `classKeys` from the classify result. The compile handler that calls `classify` and then `emit-classes` needs to also pass pipe keys.

Find the compile handler that bridges classify → emit-classes and pass pipe keys through. Pipe keys are emitted via `emit-class` with the same mechanism but are marked as pipe entries so `wrapCollectedClasses` can skip them.

In `emit-classes.nix`, update the handler to also emit pipe keys:

```nix
"emit-classes" =
  { param, state }:
  let
    aspect = param.aspect;
    classKeys = param.classKeys;
    pipeKeys = param.pipeKeys or [ ];
    nodeIdentity = param.identity;
    ctx = ctxFromHandlers (aspect.__scopeHandlers or { });
    aspectPolicy = aspect.meta.collisionPolicy or null;
    globalPolicy = den.config.classModuleCollisionPolicy or "error";
    contextDep = isContextDep aspect ctx;
    # Pipe keys emit with __isPipeEntry = true so wrapCollectedClasses skips them
    emitPipeKey = k:
      let
        modules = unwrapContentValuesList aspect.${k};
        isMulti = builtins.length modules > 1;
        mkEntry = idx: module:
          fx.send "emit-class" {
            class = k;
            identity = if isMulti then "${nodeIdentity}[${toString idx}]" else nodeIdentity;
            inherit module ctx;
            aspectPolicy = null;
            globalPolicy = null;
            isContextDependent = contextDep;
            __rawEntry = true;
            __isPipeEntry = true;
          };
      in
      fx.seq (lib.imap0 mkEntry modules);
  in
  {
    resume = fx.seq (
      (map (emitClassKey aspect ctx aspectPolicy globalPolicy contextDep nodeIdentity) classKeys)
      ++ (map emitPipeKey pipeKeys)
    );
    inherit state;
  };
```

- [ ] **Step 4: Update compile-static handler to pass pipeKeys to emit-classes**

In `handlers/compile-static.nix:79`, where `emit-classes` is called, add `pipeKeys` from the classify result:

```nix
# compile-static.nix:79 — add pipeKeys to the emit-classes param:
(fx.send "emit-classes" {
  aspect = tagged;
  classKeys = classified.classKeys;
  pipeKeys = classified.pipeKeys or [];
  identity = nodeIdentity;
})
```

- [ ] **Step 5: Skip pipe entries in `wrapCollectedClasses`**

In `wrap-classes.nix` (line ~160), skip wrapping for pipe entries:

```nix
wrapCollectedClasses =
  enrichedCtx: classImports:
  lib.mapAttrs (
    class: entries:
    lib.concatMap (
      entry:
      if entry.__isPipeEntry or false then
        [ entry ]  # Pass through raw — assemblePipes handles these
      else if !(entry.__rawEntry or false) then
        [ entry ]
      else
        processEntry enrichedCtx class entry
    ) entries
  ) classImports;
```

- [ ] **Step 6: Write classification tests**

Add to `templates/ci/modules/features/pipes.nix`:

```nix
# Pipe key reaches scopedClassImports, not emitted as class module.
test-pipe-key-collected = denTest (
  { den, igloo, ... }:
  {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.pipes.firewall = { description = "Firewall port declarations"; };
    den.aspects.igloo = {
      nixos.networking.hostName = "pipe-classify";
      firewall = { ports = [ 80 443 ]; };
    };
    # firewall quirk should NOT become a NixOS module import.
    # If it did, NixOS would error on unrecognized { ports = [...]; }.
    expr = igloo.networking.hostName;
    expected = "pipe-classify";
  }
);
```

```bash
nix develop -c just fmt
nix develop -c just ci
git commit -c commit.gpgsign=false -m "feat(pipes): classify pipe keys separately from class keys"
```

---

### Task 3: Local Scope Consumption — `assemblePipes` and `wrapClassModule` Delivery

**Goal:** Aspects on the same host can emit quirks on pipe keys and consume them as function args. This is the core firewall aggregation use case.

**Files:**
- Create: `nix/lib/aspects/fx/assemble-pipes.nix`
- Modify: `nix/lib/aspects/fx/resolve.nix:191-216`
- Modify: `nix/lib/aspects/fx/key-classification.nix` (export `pipeRegistry`)
- Test: `templates/ci/modules/features/pipes.nix`

**Acceptance Criteria:**
- [ ] Multiple aspects emit quirks on same pipe key, consumer receives aggregated list
- [ ] Consumer receives `[]` for declared pipes with no emissions
- [ ] List-valued quirks are auto-flattened
- [ ] Consumer in `nixos` module receives pipe data via function args
- [ ] Pipeline-time discriminators (in `includes`) can use pipe args (deferred until siblings emit)

**Verify:** `nix develop -c just ci` → all pass

**Steps:**

- [ ] **Step 1: Create `assemble-pipes.nix`**

```nix
# Post-pipeline phase: assemble pipe data from scopedClassImports
# and inject into scope contexts for delivery via wrapClassModule.
{
  lib,
  den,
  ...
}:
let
  pipeRegistry = den.pipes or { };
  pipeNames = builtins.attrNames pipeRegistry;

  # Flatten list-valued quirk entries.
  flattenEntries =
    entries:
    builtins.concatMap (
      entry:
      let
        val = entry.module or entry;
      in
      if builtins.isList val then
        map (v: { module = v; __isPipeEntry = true; }) val
      else
        [ entry ]
    ) entries;

  # Extract raw quirk values from pipe entries.
  extractValues =
    entries:
    map (
      entry:
      entry.module or entry
    ) entries;

  # Assemble pipe data for all scopes.
  # Returns augmented scopeContexts with pipe data injected as keys.
  assemblePipes =
    {
      scopeContexts,
      scopedClassImports,
      scopedPipeEffects ? { },
    }:
    let
      # For each scope, collect pipe data from scopedClassImports.
      augmentScope =
        scopeId: scopeCtx:
        let
          scopeImports = scopedClassImports.${scopeId} or { };
          pipeData = lib.genAttrs pipeNames (
            pipeName:
            let
              rawEntries = scopeImports.${pipeName} or [ ];
              flattened = flattenEntries rawEntries;
            in
            extractValues flattened
          );
        in
        scopeCtx // pipeData;
    in
    lib.mapAttrs augmentScope scopeContexts;
in
{
  inherit assemblePipes;
}
```

- [ ] **Step 2: Wire `assemblePipes` into `resolve.nix`**

In `resolve.nix`, insert `assemblePipes` before `wrapPerScope` (after line 200):

```nix
# In fxResolve, after result and scopeContexts:
result = mkPipeline { inherit class; } { inherit self ctx; };
scopeContexts = result.state.scopeContexts null;

# NEW: Assemble pipe data and augment scope contexts
augmentedScopeContexts =
  let
    inherit (import ./assemble-pipes.nix { inherit lib den; }) assemblePipes;
  in
  assemblePipes {
    inherit scopeContexts;
    scopedClassImports = result.state.scopedClassImports null;
  };

# Pass augmented contexts to wrapPerScope (pipe data now in ctx)
phase1 = wrapPerScope ctx augmentedScopeContexts (result.state.scopedClassImports null);
phase2 = applyProvides ctx augmentedScopeContexts (result.state.scopedProvides null) phase1;
phase3 =
  applyRoutes (fxResolve mkPipeline) ctx augmentedScopeContexts result.state.rootScopeId
    (result.state.scopedRoutes null)
    phase2;
```

- [ ] **Step 3: Write local consumption tests**

Add to `templates/ci/modules/features/pipes.nix`:

```nix
# Firewall aggregation: multiple producers, one consumer.
test-pipe-local-consumption = denTest (
  { den, igloo, ... }:
  {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.pipes.firewall = { description = "Firewall port declarations"; };

    den.aspects.igloo = {
      includes = [
        den.aspects.nginx
        den.aspects.postgres
        den.aspects.networking
      ];
    };

    den.aspects.nginx = {
      nixos.services.nginx.enable = true;
      firewall = { ports = [ 80 443 ]; };
    };
    den.aspects.postgres = {
      nixos.services.postgresql.enable = true;
      firewall = { ports = [ 5432 ]; };
    };

    den.aspects.networking = {
      nixos = { firewall, lib, ... }: {
        networking.firewall.allowedTCPPorts =
          lib.concatMap (f: f.ports or []) firewall;
      };
    };

    expr = igloo.networking.firewall.allowedTCPPorts;
    expected = [ 80 443 5432 ];
  }
);

# Empty pipe returns [].
test-pipe-empty = denTest (
  { den, igloo, ... }:
  {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.pipes.firewall = { description = "Firewall port declarations"; };

    den.aspects.igloo = {
      includes = [ den.aspects.networking ];
    };

    den.aspects.networking = {
      nixos = { firewall, lib, ... }: {
        networking.firewall.allowedTCPPorts =
          lib.concatMap (f: f.ports or []) firewall;
      };
    };

    expr = igloo.networking.firewall.allowedTCPPorts;
    expected = [ ];
  }
);

# List-valued quirks are auto-flattened.
test-pipe-list-flatten = denTest (
  { den, igloo, ... }:
  {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.pipes.items = { description = "List items"; };

    den.aspects.igloo = {
      includes = [ den.aspects.producer den.aspects.consumer ];
    };

    den.aspects.producer = {
      items = [ { name = "a"; } { name = "b"; } ];
    };

    den.aspects.consumer = {
      nixos = { items, lib, ... }: {
        networking.hostName = lib.concatMapStringsSep "-" (i: i.name) items;
      };
    };

    expr = igloo.networking.hostName;
    expected = "a-b";
  }
);
```

- [ ] **Step 4: Handle discriminator deferral for pipe args in `bind.nix`**

The spec requires pipeline-time discriminators with pipe args to be deferred during `emitIncludes` and drained after all sibling aspects in the current scope have emitted. The bind handler must recognize pipe arg names and defer discriminators that reference them.

In `bind.nix`, add pipe recognition:

```nix
{ den, ... }:
let
  inherit (den.lib) fx;
  pipeRegistry = den.pipes or { };
in
{
  bindHandler = {
    "bind" =
      { param, state }:
      let
        inherit (param) aspect compileFn;
        childArgs = aspect.__args or { };
        childScopeHandlers = aspect.__scopeHandlers or { };
        requiredKeys = builtins.filter (k: !childArgs.${k}) (builtins.attrNames childArgs);
        keysToProbe = builtins.filter (k: !(childScopeHandlers ? ${k})) requiredKeys;
        # Pipe args are never scope handlers — they're populated post-walk.
        # If any required key is a pipe name, defer unconditionally.
        hasPipeArgs = builtins.any (k: pipeRegistry ? ${k}) requiredKeys;
        probeArgs = ...;  # existing probe logic
      in
      {
        resume = fx.bind (probeArgs keysToProbe) (
          allAvailable:
          if allAvailable && !hasPipeArgs then
            fx.bind (compileFn aspect) (result: fx.pure { value = result; })
          else
            fx.bind (fx.send "defer" {
              child = aspect;
              inherit requiredKeys;
              requiredArgs = keysToProbe;
              # Tag pipe-arg deferred includes for post-walk resolution
              __hasPipeArgs = hasPipeArgs;
            }) (_: fx.pure { deferred = true; })
        );
        inherit state;
      };
  };
}
```

Pipe-arg discriminators will be deferred and remain in `scopedDeferredIncludes` through the entire walk (drain can never satisfy them — pipe args aren't scope handlers). After `assemblePipes` injects pipe data into `scopeContexts`, pipe-arg deferred includes must be resolved.

Add a post-assembly drain pass in `resolve.nix`: after `assemblePipes` augments scope contexts with pipe data, iterate `scopedDeferredIncludes` for entries tagged `__hasPipeArgs = true`. For each, call the deferred discriminator function with the assembled pipe data as args. The result (includes/aspect data) is then processed through `emitIncludes` and the resulting class modules are added to `scopedClassImports` before `wrapPerScope`.

```nix
# In resolve.nix, after assemblePipes:
# Resolve pipe-arg deferred discriminators
pipeArgDeferred = builtins.filter
  (d: d.__hasPipeArgs or false)
  (lib.concatLists (builtins.attrValues (result.state.scopedDeferredIncludes null)));

# For each deferred discriminator with pipe args:
# 1. Get the scope's assembled pipe data from augmentedScopeContexts
# 2. Call the deferred aspect's __fn with pipe args
# 3. Process the result (includes → emit-class → scopedClassImports)
```

This is the most subtle part of Phase 2. The deferred function needs to be called with the assembled pipe data, and any class modules it produces must be folded into `scopedClassImports` before `wrapPerScope`. Since Nix is lazy, this can be done by extending `augmentedScopeContexts` computation to also process pipe-arg deferred includes.

- [ ] **Step 5: Write discriminator deferral tests**

Add to `templates/ci/modules/features/pipes.nix`:

```nix
# Pipeline-time discriminator: conditional inclusion based on pipe data.
# Producer appears AFTER discriminator in includes — verify correct result
# regardless of include order.
test-pipe-discriminator = denTest (
  { den, igloo, ... }:
  {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.pipes.firewall = { description = "Firewall port declarations"; };

    den.aspects.igloo = {
      includes = [
        # Discriminator first — must be deferred until siblings emit
        den.aspects.secure-server
        # Producer second — emits firewall quirk
        den.aspects.nginx
      ];
    };

    den.aspects.secure-server = {
      includes = [
        ({ firewall, ... }:
          let hasHttps = builtins.any (f: builtins.elem 443 (f.ports or [])) firewall;
          in lib.optionalAttrs hasHttps {
            includes = [ den.aspects.tls-hardening ];
          })
      ];
    };

    den.aspects.nginx = {
      nixos.services.nginx.enable = true;
      firewall = { ports = [ 80 443 ]; };
    };

    den.aspects.tls-hardening = {
      nixos.networking.hostName = "hardened";
    };

    expr = igloo.networking.hostName;
    expected = "hardened";
  }
);

# Discriminator with no matching pipes — gets empty list.
test-pipe-discriminator-empty = denTest (
  { den, igloo, ... }:
  {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.pipes.firewall = { description = "Firewall port declarations"; };

    den.aspects.igloo = {
      includes = [ den.aspects.secure-server ];
    };

    den.aspects.secure-server = {
      includes = [
        ({ firewall, ... }:
          let hasHttps = builtins.any (f: builtins.elem 443 (f.ports or [])) firewall;
          in lib.optionalAttrs hasHttps {
            includes = [ den.aspects.tls-hardening ];
          })
      ];
      nixos.networking.hostName = "not-hardened";
    };

    den.aspects.tls-hardening = {
      nixos.networking.hostName = "hardened";
    };

    expr = igloo.networking.hostName;
    expected = "not-hardened";
  }
);
```

```bash
nix develop -c just fmt
nix develop -c just ci
git commit -c commit.gpgsign=false -m "feat(pipes): local scope consumption via assemblePipes"
```

---

### Task 4: Policy Pipe Builder — Transform Stages

**Goal:** Policies can filter, transform, fold, append, and aggregate pipe data within a scope using `pipe.from` and stage constructors.

**Files:**
- Create: `nix/lib/aspects/fx/pipe-builder.nix`
- Create: `nix/lib/aspects/fx/handlers/register-pipe-effect.nix`
- Modify: `nix/lib/policy-effects.nix:1-167` (add `pipe` namespace)
- Modify: `nix/lib/aspects/fx/policy/dispatch.nix:10-17` (add `"pipe"` to valid effect types)
- Modify: `nix/lib/aspects/fx/policy/classify.nix:43-67` (extract pipe effects)
- Modify: `nix/lib/aspects/fx/handlers/emit-policy-effects.nix:13-53` (emit pipe effects)
- Modify: `nix/lib/aspects/fx/handlers/default.nix` (import register-pipe-effect)
- Modify: `nix/lib/aspects/fx/pipeline.nix:143-181` (add `scopedPipeEffects` to default state)
- Modify: `nix/lib/aspects/fx/assemble-pipes.nix` (apply pipe effects)
- Modify: `nix/lib/aspects/fx/resolve.nix` (pass `scopedPipeEffects` to `assemblePipes`)
- Create: `templates/ci/modules/features/pipe-policy.nix`

**Acceptance Criteria:**
- [ ] `pipe.from den.pipes.X [ (pipe.filter ...) ]` returns a valid `__policyEffect = "pipe"` effect
- [ ] Transform stages (filter, transform, fold, append, for) apply in declared order
- [ ] `pipe.for` limited to one per pipe per scope — multiple is an error
- [ ] Multiple `pipe.from` in one policy works correctly
- [ ] Pipe effects from multiple policies targeting same pipe are merged

**Verify:** `nix develop -c just ci` → all pass

**Steps:**

- [ ] **Step 1: Create pipe builder API in `pipe-builder.nix`**

```nix
# Pipe builder API: pipe.from, pipe.filter, pipe.transform, etc.
# Returns __policyEffect = "pipe" effects consumed by the pipeline.
{ lib, ... }:
let
  mkStage = type: fn: {
    __pipeStage = type;
    inherit fn;
  };
in
{
  pipe = {
    # Entry point: source pipe ref + ordered list of stages.
    from = pipeRef: stages: {
      __policyEffect = "pipe";
      value = {
        pipeName = pipeRef.name or (
          # pipeRef is the den.pipes.X attrset — extract name from __toString or key
          throw "den: pipe.from requires a pipe reference (den.pipes.<name>)"
        );
        inherit stages;
      };
    };

    # Transform stages
    filter = pred: mkStage "filter" pred;
    transform = fn: mkStage "transform" fn;
    fold = fn: init: { __pipeStage = "fold"; inherit fn init; };
    append = value: { __pipeStage = "append"; inherit value; };
    for = fn: mkStage "for" fn;
    withProvenance = { __pipeStage = "withProvenance"; };

    # Routing stages
    to = aspects: { __pipeStage = "to"; inherit aspects; };
    expose = { __pipeStage = "expose"; };
    collect = pred: mkStage "collect" pred;
  };
}
```

Note: The `pipeRef` design needs careful thought. `den.pipes.firewall` evaluates to the pipe's metadata attrset `{ description = "..."; }`. We need a way to extract the pipe name. Options:
1. The `den.pipes` type coerces each entry to include a `name` field (like aspects)
2. We pass the pipe name as a string: `pipe.from "firewall" [...]`
3. We use the registry key during `assemblePipes` to match

**Decision:** Use string pipe names: `pipe.from "firewall" [...]`. This is simplest and avoids type system changes. The `assemblePipes` phase validates that the name exists in `den.pipes`.

Updated API:

```nix
from = pipeName: stages: {
  __policyEffect = "pipe";
  value = {
    inherit pipeName stages;
  };
};
```

- [ ] **Step 2: Add `pipe` to `policy-effects.nix`**

After the `provide` definition (~line 89), add:

```nix
# Pipe builder — structured data flow through named pipes.
# Returns __policyEffect = "pipe" effects processed by assemblePipes.
pipe =
  let
    inherit (import ./aspects/fx/pipe-builder.nix { inherit lib; }) pipe;
  in
  pipe;
```

Wait — `policy-effects.nix` takes `{ ... }:` (no named args). It can't import from aspects/fx/. Better to inline the pipe builder here or make it standalone. Since the pipe builder is small, inline it:

```nix
# After provide definition:
pipe = {
  from = pipeName: stages: {
    __policyEffect = "pipe";
    value = { inherit pipeName stages; };
  };
  filter = pred: { __pipeStage = "filter"; fn = pred; };
  transform = fn: { __pipeStage = "transform"; inherit fn; };
  fold = fn: init: { __pipeStage = "fold"; inherit fn init; };
  append = value: { __pipeStage = "append"; inherit value; };
  for = fn: { __pipeStage = "for"; inherit fn; };
  withProvenance = { __pipeStage = "withProvenance"; };
  to = aspects: { __pipeStage = "to"; inherit aspects; };
  expose = { __pipeStage = "expose"; };
  collect = pred: { __pipeStage = "collect"; fn = pred; };
};
```

- [ ] **Step 3: Add `"pipe"` to valid effect types in `dispatch.nix`**

In `policy/dispatch.nix` (line 10-17):

```nix
validEffectTypes = {
  resolve = true;
  include = true;
  exclude = true;
  route = true;
  instantiate = true;
  provide = true;
  pipe = true;
};
```

- [ ] **Step 4: Extract pipe effects in `classify.nix`**

In `policy/classify.nix`, add pipe effect extraction (after `provideEffects` line ~66):

```nix
pipeEffects = filterEffect "pipe" r.effects;
```

Update `hasEffects` (~line 81) to include pipe:

```nix
|| r.pipeEffects != [ ]
```

Update `extractTaggedEffects` (~line 122) to collect pipe effects:

```nix
pipeEffects = builtins.concatMap (
  r: map (pe: pe // { __pipePolicyName = r.policyName; }) r.pipeEffects
) classified;
```

- [ ] **Step 5: Create `register-pipe-effect` handler**

Create `nix/lib/aspects/fx/handlers/register-pipe-effect.nix`:

```nix
# Effect handler: register-pipe-effect
# Collects pipe effects into scopedPipeEffects with scope-aware accumulation.
_:
let
  inherit (import ./state-util.nix) scopedAppend;

  registerPipeEffectHandler = {
    "register-pipe-effect" =
      { param, state }:
      let
        scope = state.currentScope;
      in
      {
        resume = null;
        state = scopedAppend state "scopedPipeEffects" scope
          (param // { sourceScopeId = scope; });
      };
  };
in
{
  inherit registerPipeEffectHandler;
}
```

- [ ] **Step 6: Wire handler and state**

In `handlers/default.nix`, add import:

```nix
// (import ./register-pipe-effect.nix args)
```

In `pipeline.nix` `defaultState` (~line 160), add:

```nix
scopedPipeEffects = _: { };
```

- [ ] **Step 7: Emit pipe effects in `policy/apply.nix`**

The emission logic lives in `nix/lib/aspects/fx/policy/apply.nix` (specifically the `emitPolicyEffectsThen` function). The handler in `emit-policy-effects.nix` delegates to `apply.nix`. Add pipe effect emission to `emitPolicyEffectsThen`:

```nix
# In policy/apply.nix, inside emitPolicyEffectsThen, after route/instantiate/provide emissions:
# Pipe effects → register-pipe-effect
pipeRegs = fx.seq (map (pe: fx.send "register-pipe-effect" pe.value) effects.pipeEffects or []);
```

Add `pipeRegs` to the `fx.seq` chain in `emitPolicyEffectsThen` alongside the existing exclude/route/instantiate/provide registrations.

- [ ] **Step 8: Apply pipe effects in `assemble-pipes.nix`**

Update `assemblePipes` to accept and apply `scopedPipeEffects`:

```nix
assemblePipes =
  {
    scopeContexts,
    scopedClassImports,
    scopedPipeEffects ? { },
  }:
  let
    augmentScope =
      scopeId: scopeCtx:
      let
        scopeImports = scopedClassImports.${scopeId} or { };
        scopePipeEffects = scopedPipeEffects.${scopeId} or [ ];
        pipeData = lib.genAttrs pipeNames (
          pipeName:
          let
            rawEntries = scopeImports.${pipeName} or [ ];
            flattened = flattenEntries rawEntries;
            values = extractValues flattened;
            # Find pipe effects targeting this pipe
            relevantEffects = builtins.filter
              (e: e.pipeName == pipeName) scopePipeEffects;
          in
          applyPipeEffects pipeName scopeId values relevantEffects
        );
      in
      scopeCtx // pipeData;
  in
  lib.mapAttrs augmentScope scopeContexts;

# Apply pipe effects in declared order.
applyPipeEffects =
  pipeName: scopeId: values: effects:
  let
    # Each effect has stages. Apply each effect independently,
    # then merge results based on targeting.
    applyEffect =
      effect:
      let
        stages = effect.stages or [ ];
        # Terminal routing stages (to, expose, collect) are handled separately.
        transformStages = builtins.filter
          (s: builtins.elem (s.__pipeStage or "") [ "filter" "transform" "fold" "append" "for" ])
          stages;
        routingStage = lib.findFirst
          (s: builtins.elem (s.__pipeStage or "") [ "to" "expose" "collect" ])
          null stages;
      in
      {
        result = builtins.foldl' applyStage values transformStages;
        routing = routingStage;
        policyName = effect.__pipePolicyName or "<anon>";
      };

    applied = map applyEffect effects;

    # Enforce pipe.for singularity: at most one per pipe per scope.
    forCount = builtins.length (builtins.filter (a:
      builtins.any (s: (s.__pipeStage or "") == "for") (a.stages or [])
    ) effects);
    _ = assert forCount <= 1
      || throw "den: multiple pipe.for on '${pipeName}' in scope '${scopeId}' from policies: ${
        lib.concatMapStringsSep ", " (e: e.__pipePolicyName or "<anon>") (
          builtins.filter (e:
            builtins.any (s: (s.__pipeStage or "") == "for") (e.stages or [])
          ) effects
        )
      }";

    # Merge untargeted results (no routing = scope-wide).
    untargeted = builtins.filter (a: a.routing == null) applied;
    # For now (Phase 3), only untargeted. pipe.to is Phase 4.
    mergedValues =
      if untargeted == [ ] then values
      else lib.concatMap (a: if builtins.isList a.result then a.result else [ a.result ]) untargeted;
  in
  if effects == [ ] then values
  else builtins.seq _ mergedValues;

# Apply a single transform stage to a value list.
applyStage =
  values: stage:
  let
    t = stage.__pipeStage or "";
  in
  if t == "filter" then builtins.filter stage.fn values
  else if t == "transform" then map stage.fn values
  else if t == "fold" then builtins.foldl' (acc: elem: stage.fn elem acc) stage.init values
  else if t == "append" then values ++ [ stage.value ]
  else if t == "for" then stage.fn values
  else values;
```

- [ ] **Step 9: Pass `scopedPipeEffects` in `resolve.nix`**

Update `fxResolve` to pass `scopedPipeEffects` to `assemblePipes`:

```nix
augmentedScopeContexts =
  let
    inherit (import ./assemble-pipes.nix { inherit lib den; }) assemblePipes;
  in
  assemblePipes {
    inherit scopeContexts;
    scopedClassImports = result.state.scopedClassImports null;
    scopedPipeEffects = result.state.scopedPipeEffects null;
  };
```

- [ ] **Step 10: Write policy transform tests**

Create `templates/ci/modules/features/pipe-policy.nix`:

```nix
{ denTest, lib, ... }:
{
  flake.tests.pipe-policy = {

    # Filter: remove entries that don't match predicate.
    test-pipe-filter = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.pipes.firewall = { description = "Firewall port declarations"; };

        den.policies.filter-internal = { host, ... }:
          let inherit (den.lib.policy) pipe; in [
            (pipe.from "firewall" [
              (pipe.filter (e: !(e.internal or false)))
            ])
          ];

        den.default.includes = [ den.policies.filter-internal ];

        den.aspects.igloo = {
          includes = [ den.aspects.web den.aspects.networking ];
        };

        den.aspects.web = {
          firewall = [
            { ports = [ 80 ]; }
            { ports = [ 9999 ]; internal = true; }
          ];
        };

        den.aspects.networking = {
          nixos = { firewall, lib, ... }: {
            networking.firewall.allowedTCPPorts =
              lib.concatMap (f: f.ports or []) firewall;
          };
        };

        expr = igloo.networking.firewall.allowedTCPPorts;
        expected = [ 80 ];
      }
    );

    # Append: add monitoring ports via policy.
    test-pipe-append = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.pipes.firewall = { description = "Firewall port declarations"; };

        den.policies.add-monitoring = { host, ... }:
          let inherit (den.lib.policy) pipe; in [
            (pipe.from "firewall" [
              (pipe.append { ports = [ 9100 ]; })
            ])
          ];

        den.default.includes = [ den.policies.add-monitoring ];

        den.aspects.igloo = {
          includes = [ den.aspects.web den.aspects.networking ];
        };

        den.aspects.web = {
          firewall = { ports = [ 80 ]; };
        };

        den.aspects.networking = {
          nixos = { firewall, lib, ... }: {
            networking.firewall.allowedTCPPorts =
              lib.concatMap (f: f.ports or []) firewall;
          };
        };

        expr = igloo.networking.firewall.allowedTCPPorts;
        expected = [ 80 9100 ];
      }
    );

    # Fold: reduce to a flat port list.
    test-pipe-fold = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.pipes.firewall = { description = "Firewall port declarations"; };

        den.policies.fold-ports = { host, ... }:
          let inherit (den.lib.policy) pipe; in [
            (pipe.from "firewall" [
              (pipe.fold (elem: acc: acc ++ (elem.ports or [])) [])
            ])
          ];

        den.default.includes = [ den.policies.fold-ports ];

        den.aspects.igloo = {
          includes = [ den.aspects.web den.aspects.consumer ];
        };

        den.aspects.web = {
          firewall = [
            { ports = [ 80 443 ]; }
            { ports = [ 5432 ]; }
          ];
        };

        den.aspects.consumer = {
          nixos = { firewall, ... }: {
            networking.firewall.allowedTCPPorts = firewall;
          };
        };

        expr = igloo.networking.firewall.allowedTCPPorts;
        expected = [ 80 443 5432 ];
      }
    );

    # pipe.for: aggregate transform.
    test-pipe-for = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.pipes.secrets = { description = "Secret paths"; };

        den.policies.merge-secrets = { host, ... }:
          let inherit (den.lib.policy) pipe; in [
            (pipe.from "secrets" [
              (pipe.for lib.mergeAttrsList)
            ])
          ];

        den.default.includes = [ den.policies.merge-secrets ];

        den.aspects.igloo = {
          includes = [ den.aspects.db den.aspects.consumer ];
        };

        den.aspects.db = {
          secrets = { db-pass = "/run/secrets/db"; };
        };

        den.aspects.consumer = {
          nixos = { secrets, ... }: {
            networking.hostName = secrets.db-pass or "missing";
          };
        };

        expr = igloo.networking.hostName;
        expected = "/run/secrets/db";
      }
    );
  };
}
```

```bash
git add nix/lib/aspects/fx/pipe-builder.nix nix/lib/aspects/fx/handlers/register-pipe-effect.nix templates/ci/modules/features/pipe-policy.nix
nix develop -c just fmt
nix develop -c just ci
git commit -c commit.gpgsign=false -m "feat(pipes): policy pipe builder with transform stages"
```

---

### Task 5: Aspect Targeting — `pipe.to`

**Goal:** Policies can narrow pipe delivery to specific aspects via `pipe.to`. Different aspects can receive different pipe data for the same pipe name.

**Files:**
- Modify: `nix/lib/aspects/fx/assemble-pipes.nix` (implement targeted delivery)
- Modify: `nix/lib/aspects/fx/wrap-classes.nix` (per-aspect pipe context)
- Modify: `nix/lib/aspects/fx/class-module.nix` (accept aspect-targeted pipe overrides)
- Test: `templates/ci/modules/features/pipe-policy.nix`

**Acceptance Criteria:**
- [ ] `pipe.to [ den.aspects.postgres ]` delivers pipe data only to postgres
- [ ] Two policies targeting different aspects on same pipe deliver independently
- [ ] Two policies targeting same aspect concatenate results
- [ ] Untargeted and targeted coexist (targeted overrides for specific aspect)

**Verify:** `nix develop -c just ci` → all pass

**Steps:**

- [ ] **Step 1: Track aspect identity in pipe entries**

When `emit-class` collects pipe entries, the entry already contains the aspect's identity. During `assemblePipes`, track which aspect emitted each quirk and which aspect each class module belongs to.

The key challenge: `pipe.to [ den.aspects.postgres ]` means "only deliver to class modules that belong to the postgres aspect". During `wrapPerScope`, we need to know which aspect each class module came from. This information is available in the emit-class entry's `identity` field.

- [ ] **Step 2: Implement targeted delivery in `assemblePipes`**

When pipe effects include `pipe.to` routing, `assemblePipes` produces per-aspect pipe overrides instead of scope-wide data:

```nix
# In assemblePipes, for each pipe with targeted effects:
# 1. Compute scope-wide data (from untargeted effects or raw if no effects)
# 2. Compute per-aspect overrides (from targeted effects)
# 3. Store both: scope-wide in scopeCtx, per-aspect in a separate structure
```

The per-aspect overrides need to reach `wrapClassModule`. Add a `__pipeOverrides` key to the scope context:

```nix
scopeCtx // pipeData // {
  __pipeOverrides = {
    # aspectIdentity → { pipeName → overrideData }
  };
}
```

Then in `wrapClassModule` (or `processEntry` in `wrap-classes.nix`), check if the current entry's aspect identity has pipe overrides and merge them into `ctx` before wrapping.

- [ ] **Step 3: Wire per-aspect overrides in `wrap-classes.nix`**

In `processEntry` (~line 112), after computing `enrichment`, check for pipe overrides:

```nix
# After enrichment merge, apply per-aspect pipe overrides:
pipeOverrides = ctx.__pipeOverrides or { };
aspectId = # extract from entry.identity
effectiveCtx =
  if pipeOverrides ? ${aspectId} then
    ctx // pipeOverrides.${aspectId}
  else
    ctx;
```

- [ ] **Step 4: Write targeting tests**

Add to `templates/ci/modules/features/pipe-policy.nix`:

```nix
# Aspect-targeted secrets: different aspects get different data.
test-pipe-to-aspect = denTest (
  { den, igloo, ... }:
  {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.pipes.secrets = { description = "Secret paths"; };

    den.policies.app-secrets = { host, ... }:
      let inherit (den.lib.policy) pipe; in [
        (pipe.from "secrets" [
          (pipe.filter (_: false))
          (pipe.append { db-password = "/run/secrets/pg-pass"; })
          (pipe.for lib.mergeAttrsList)
          (pipe.to [ den.aspects.postgres ])
        ])
        (pipe.from "secrets" [
          (pipe.filter (_: false))
          (pipe.append { cert-key = "/run/secrets/nginx-key"; })
          (pipe.for lib.mergeAttrsList)
          (pipe.to [ den.aspects.nginx-server ])
        ])
      ];

    den.default.includes = [ den.policies.app-secrets ];

    den.aspects.igloo = {
      includes = [
        den.aspects.postgres
        den.aspects.nginx-server
      ];
    };

    den.aspects.postgres = {
      nixos = { secrets, ... }: {
        networking.hostName = secrets.db-password or "missing";
      };
    };

    den.aspects.nginx-server = {
      nixos = { secrets, ... }: {
        networking.domain = secrets.cert-key or "missing";
      };
    };

    expr = {
      host = igloo.networking.hostName;
      domain = igloo.networking.domain;
    };
    expected = {
      host = "/run/secrets/pg-pass";
      domain = "/run/secrets/nginx-key";
    };
  }
);
```

```bash
nix develop -c just fmt
nix develop -c just ci
git commit -c commit.gpgsign=false -m "feat(pipes): aspect targeting with pipe.to"
```

---

### Task 6: `pipe.expose` — Upward Scope Flow

**Goal:** Child scope pipe data can be pushed to the parent scope. User-emitted quirks become visible at the host level.

**Files:**
- Modify: `nix/lib/aspects/fx/assemble-pipes.nix` (bottom-up assembly, expose processing)
- Test: `templates/ci/modules/features/pipe-scope.nix`

**Acceptance Criteria:**
- [ ] `pipe.expose` pushes data from child scope to parent
- [ ] Parent scope consumers see exposed data alongside local quirks
- [ ] Exposed data is NOT visible to sibling scopes
- [ ] Transform stages before `pipe.expose` are applied before exposing

**Verify:** `nix develop -c just ci` → all pass

**Steps:**

- [ ] **Step 1: Implement bottom-up assembly ordering**

`assemblePipes` currently iterates scopes with `lib.mapAttrs` (unordered). For `pipe.expose`, child scopes must assemble before parents. Use `scopeParent` to determine order:

```nix
# Build scope tree from scopeParent
# Process leaves first, then parents
assemblePipes = { scopeContexts, scopedClassImports, scopedPipeEffects ? {}, scopeParent ? {} }:
let
  # Topological sort: children before parents
  allScopes = builtins.attrNames scopeContexts;
  children = scopeId:
    builtins.filter (s: (scopeParent.${s} or null) == scopeId) allScopes;

  # Process scopes bottom-up, accumulating exposed data
  processScope = exposedPool: scopeId: ...;
in ...;
```

- [ ] **Step 2: Process expose effects**

When a pipe effect has `pipe.expose` as its routing stage, after applying transform stages, merge the result into the parent scope's pipe data pool.

- [ ] **Step 3: Pass `scopeParent` to `assemblePipes`**

In `resolve.nix`, pass `scopeParent` from pipeline state:

```nix
assemblePipes {
  inherit scopeContexts;
  scopedClassImports = result.state.scopedClassImports null;
  scopedPipeEffects = result.state.scopedPipeEffects null;
  scopeParent = result.state.scopeParent null;
};
```

- [ ] **Step 4: Write expose tests**

Create `templates/ci/modules/features/pipe-scope.nix`:

```nix
{ denTest, lib, ... }:
{
  flake.tests.pipe-scope = {

    # User preferences exposed to host scope.
    test-pipe-expose = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.pipes.user-preferences = { description = "User prefs"; };

        den.policies.expose-prefs = { host, user, ... }:
          let inherit (den.lib.policy) pipe; in [
            (pipe.from "user-preferences" [
              (pipe.transform (p: p // { userName = user.name; }))
              pipe.expose
            ])
          ];

        den.default.includes = [ den.policies.expose-prefs ];

        den.aspects.tux = {
          user-preferences = { editor = "vim"; shell = "zsh"; };
        };

        den.aspects.igloo = {
          includes = [ den.aspects.shell-setup ];
        };

        den.aspects.shell-setup = {
          nixos = { user-preferences, lib, ... }: {
            programs.zsh.enable = lib.any (p: p.shell == "zsh") user-preferences;
          };
        };

        expr = igloo.programs.zsh.enable;
        expected = true;
      }
    );
  };
}
```

```bash
git add templates/ci/modules/features/pipe-scope.nix
nix develop -c just fmt
nix develop -c just ci
git commit -c commit.gpgsign=false -m "feat(pipes): upward scope flow with pipe.expose"
```

---

### Task 7: `pipe.collect` — Peer Scope Harvesting

**Goal:** Policies can reach into peer scopes and harvest their quirks. This enables cross-host service discovery.

**Files:**
- Modify: `nix/lib/aspects/fx/assemble-pipes.nix` (collect implementation)
- Test: `templates/ci/modules/features/pipe-scope.nix`

**Acceptance Criteria:**
- [ ] `pipe.collect` harvests quirks from matching peer scopes
- [ ] Current scope is auto-excluded from collection
- [ ] Collected quirks are deduped by source scope + pipe name
- [ ] Transform stages after `pipe.collect` operate on combined pool
- [ ] `pipe.collect` + `pipe.expose` compose correctly

**Verify:** `nix develop -c just ci` → all pass

**Steps:**

- [ ] **Step 1: Implement collect predicate evaluation**

In `assemblePipes`, when processing a scope with `pipe.collect` stages:

```nix
# For each collect stage:
# 1. Iterate all walked scopes (from scopeContexts)
# 2. Call predicate with each scope's context
# 3. Exclude current scope
# 4. Harvest matching scopes' raw pipe entries from scopedClassImports
# 5. Combine with local entries
# 6. Continue with remaining transform stages
```

- [ ] **Step 2: Handle predicate-based entity kind matching**

The predicate `({ host, ... }: true)` should only match scopes that have a `host` in their context. Use `builtins.tryEval` or check context keys before calling the predicate:

```nix
matchesPredicate = pred: scopeCtx:
  let
    predArgs = builtins.functionArgs pred;
    requiredArgs = builtins.filter (k: !predArgs.${k}) (builtins.attrNames predArgs);
    hasAll = builtins.all (k: scopeCtx ? ${k}) requiredArgs;
  in
  hasAll && pred scopeCtx;
```

- [ ] **Step 3: Implement dedup for collected entries**

Track `(sourceScopeId, pipeName)` pairs to prevent duplicate collection when multiple policies collect from overlapping peer sets.

- [ ] **Step 4: Write collect tests**

Add to `templates/ci/modules/features/pipe-scope.nix`:

```nix
# Cross-host backend collection (simplified — two hosts in same eval).
test-pipe-collect = denTest (
  { den, igloo, ... }:
  {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.hosts.x86_64-linux.iceberg.users.alice = { };

    den.pipes.http-backends = { description = "HTTP backends"; };

    den.policies.fleet-backends = { host, ... }:
      let inherit (den.lib.policy) pipe; in [
        (pipe.from "http-backends" [
          (pipe.collect ({ host, ... }: true))
        ])
      ];

    den.default.includes = [ den.policies.fleet-backends ];

    den.aspects.iceberg = {
      http-backends = { addr = "10.0.0.2"; port = 80; };
    };

    den.aspects.igloo = {
      includes = [ den.aspects.haproxy ];
      http-backends = { addr = "10.0.0.1"; port = 80; };
    };

    den.aspects.haproxy = {
      nixos = { http-backends, lib, ... }: {
        # Should see iceberg's backend but NOT igloo's own (self-excluded)
        networking.hostName = toString (builtins.length http-backends);
      };
    };

    expr = igloo.networking.hostName;
    expected = "1"; # Only iceberg's backend
  }
);
```

```bash
nix develop -c just fmt
nix develop -c just ci
git commit -c commit.gpgsign=false -m "feat(pipes): cross-scope collection with pipe.collect"
```

---

### Task 8: `pipe.withProvenance` and Config-Dependent Thunks

**Goal:** Full cross-host eval-time data flow with source context access and lazy config references.

**Files:**
- Modify: `nix/lib/aspects/fx/assemble-pipes.nix` (provenance wrapping, config thunk detection + resolution)
- Modify: `nix/lib/aspects/fx/resolve.nix` (lazy forward reference to instantiated configs)
- Test: `templates/ci/modules/features/pipe-scope.nix`

**Acceptance Criteria:**
- [ ] `pipe.withProvenance` wraps entries as `{ value, source }` with source scope context
- [ ] Config-dependent thunks (`{ config, ... }: ...`) detected and resolved lazily
- [ ] Thunk resolution uses lazy forward reference to instantiated configs
- [ ] List-valued thunk results are auto-flattened
- [ ] Mutual config dependencies work (non-overlapping attribute access)

**Verify:** `nix develop -c just ci` → all pass

**Steps:**

- [ ] **Step 1: Implement provenance wrapping**

In `assemblePipes`, when processing `withProvenance` stage:

```nix
# Wrap each entry with source scope context
applyProvenance = entries: sourceCtxs:
  map (entry:
    let
      sourceCtx = sourceCtxs.${entry.__sourceScopeId or "?"} or {};
    in
    { value = entry; source = sourceCtx; }
  ) entries;
```

This requires tracking which scope each entry came from. Pipe entries in `scopedClassImports` are already scope-partitioned — the scope ID is the key. When `pipe.collect` merges entries from multiple scopes, annotate each with its source scope.

- [ ] **Step 2: Implement config-dependent thunk detection**

```nix
# Module-system arg names that indicate config dependency
configArgNames = lib.genAttrs [ "config" "lib" "pkgs" "options" "modulesPath" ] (_: true);

isConfigDependent = entry:
  builtins.isFunction entry
  && builtins.any (k: configArgNames ? ${k})
    (builtins.attrNames (builtins.functionArgs entry));
```

- [ ] **Step 3: Implement lazy forward reference in `resolve.nix`**

Use Nix's recursive `let` to create a forward reference from `assemblePipes` to instantiated configs:

```nix
# In fxResolve:
let
  result = mkPipeline { inherit class; } { inherit self ctx; };
  scopeContexts = result.state.scopeContexts null;

  augmentedScopeContexts =
    let
      inherit (import ./assemble-pipes.nix { inherit lib den; }) assemblePipes;
    in
    assemblePipes {
      inherit scopeContexts;
      scopedClassImports = result.state.scopedClassImports null;
      scopedPipeEffects = result.state.scopedPipeEffects null;
      scopeParent = result.state.scopeParent null;
      hostConfigs = instantiatedConfigs; # lazy forward ref
    };

  phase1 = wrapPerScope ctx augmentedScopeContexts ...;
  ...
  phase4 = applyInstantiates ...;
  instantiatedConfigs = extractLazyConfigs phase4;
in ...;
```

The `extractLazyConfigs` function maps scope IDs to their instantiated `evalModules` configs. This is the most subtle part — it creates a circular dependency that works only because Nix evaluates lazily and the accessed attributes don't transitively depend on themselves.

- [ ] **Step 4: Resolve config thunks in `assemblePipes`**

```nix
resolveEntry = hostConfigs: sourceScopeId: entry:
  if isConfigDependent entry then
    entry {
      config = hostConfigs.${sourceScopeId} or {};
      inherit lib;
    }
  else
    entry;
```

- [ ] **Step 5: Write config thunk and provenance tests**

Add to `templates/ci/modules/features/pipe-scope.nix`:

```nix
# Config-dependent thunk: aspect emits function, resolved lazily.
test-pipe-config-thunk = denTest (
  { den, igloo, ... }:
  {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.pipes.host-info = { description = "Host info"; };

    den.aspects.igloo = {
      includes = [ den.aspects.info-provider den.aspects.info-consumer ];
    };

    den.aspects.info-provider = {
      nixos.networking.hostName = "thunk-test";
      host-info = { config, ... }: {
        hostname = config.networking.hostName;
      };
    };

    den.aspects.info-consumer = {
      nixos = { host-info, lib, ... }: {
        networking.domain = (builtins.head host-info).hostname;
      };
    };

    expr = igloo.networking.domain;
    expected = "thunk-test";
  }
);

# Provenance wrapping: source context available on entries.
test-pipe-provenance = denTest (
  { den, igloo, ... }:
  {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.hosts.x86_64-linux.iceberg.users.alice = { };

    den.pipes.backup-targets = { description = "Backup targets"; };

    den.policies.fleet-backup = { host, ... }:
      let inherit (den.lib.policy) pipe; in [
        (pipe.from "backup-targets" [
          (pipe.collect ({ host, ... }: true))
          pipe.withProvenance
          (pipe.transform (e: e.value // { source-host = e.source.host.name; }))
        ])
      ];

    den.default.includes = [ den.policies.fleet-backup ];

    den.aspects.iceberg = {
      backup-targets = { path = "/data"; };
    };

    den.aspects.igloo = {
      includes = [ den.aspects.backup-server ];
    };

    den.aspects.backup-server = {
      nixos = { backup-targets, lib, ... }: {
        networking.hostName =
          lib.concatMapStringsSep "," (b: b.source-host) backup-targets;
      };
    };

    expr = igloo.networking.hostName;
    expected = "iceberg";
  }
);
```

```bash
nix develop -c just fmt
nix develop -c just ci
git commit -c commit.gpgsign=false -m "feat(pipes): provenance wrapping and config-dependent thunks"
```

---

## Appendix: Key Implementation Notes

### Pipe name resolution in `pipe.from`

The spec shows `pipe.from den.pipes.firewall [...]` but `den.pipes.firewall` evaluates to `{ description = "..."; }` — no name. Options:
1. **String name** (recommended for Phase 3): `pipe.from "firewall" [...]` — simple, no type changes
2. **Name injection**: Add `name` field to pipe schema type via `_module.args.name = name;` — then `pipe.from den.pipes.firewall [...]` works via `pipeRef.name`

Start with string names. Migrate to ref-based once the type system supports it.

### `pipe.for` singularity enforcement

When multiple `pipe.for` effects target the same pipe in the same scope, `assemblePipes` must detect this and throw with provenance (policy names):

```nix
forEffects = builtins.filter (e: hasForStage e) relevantEffects;
assert builtins.length forEffects <= 1
  || throw "den: multiple pipe.for on '${pipeName}' in scope '${scopeId}' — policies: ${...}";
```

### Walk-order independence for discriminators

Pipeline-time discriminators in `includes` that reference pipe args can't work during the walk — pipe data is assembled post-walk. For Phase 2, this is documented as a limitation. If needed later, a post-walk drain pass could re-evaluate deferred discriminators with assembled pipe data.

### Interaction with routes/forwards

Routes read from `scopedClassImports.*.${fromClass}` (Phase 3 in post-pipeline). Pipes also read from `scopedClassImports.*.${pipeName}` (Phase 0 in post-pipeline). Since assemblePipes runs BEFORE routes, there's no conflict — pipes read their entries first, routes read class entries later. A key cannot be both a class and a pipe (enforced by the collision assertion).
