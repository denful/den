# Pipeline Simplification Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete entityIncludes/entityProvides/provides/rootIncludes infrastructure, extract sub-pipeline combinator, generalize flake fan-out.

**Architecture:** Self-provides move into resolveEntity as hardcoded parametric functions. Framework aspects (os-class, os-user, wsl) move to policy.aspects. A type-level deprecation shim rewrites `provides.X` to direct nesting. Test files migrate entityIncludes writes to policy.aspects or direct includes. Pipeline machinery (emitSelfProvide, emitCrossProvider, rootIncludes phase) is deleted. Three fxFullResolve call sites refactored through a thin `runSubPipeline` combinator. Flake fan-out hardcode replaced by `policy.isolateFanOut`.

**Tech Stack:** Nix module system, nix-effects, nix-unit tests

**Spec:** `docs/superpowers/specs/2026-04-26-pipeline-simplification-design.md`

---

## File Structure

### Deleted files
| File | Replaced by |
|------|------------|
| `nix/nixModule/entities.nix` | Options removed — no replacement needed |
| `modules/context/host.nix` | `resolveEntity` derives self-provide from ctx |
| `modules/context/user.nix` | Same |

### Major modifications
| File | Changes |
|------|---------|
| `nix/lib/resolve-entity.nix` | Self-provide from ctx, remove entityIncludes/entityProvides reading |
| `nix/lib/aspects/fx/aspect.nix` | Remove emitSelfProvide, mkPositionalInclude, mkNamedInclude, rootIncludes phase, provides from structuralKeysSet |
| `nix/lib/aspects/fx/pipeline.nix` | Add `runSubPipeline` combinator |
| `nix/lib/aspects/fx/handlers/transition.nix` | Remove emitCrossProvider/crossProvider, use runSubPipeline, read isolateFanOut |
| `nix/lib/aspects/fx/handlers/forward.nix` | Use runSubPipeline |
| `nix/lib/aspects/fx/handlers/policy-dispatch.nix` | Propagate isolateFanOut in routing |
| `nix/lib/aspects/types.nix` | Provides deprecation shim rewriting provides.X to direct nesting |
| `nix/lib/den-brackets.nix` | Remove `/` → `.provides.` rewrite |
| `nix/lib/policy-types.nix` | Add `isolateFanOut` option |
| `nix/lib/home-env.nix` | Add framework aspects to policy.aspects |
| `modules/options.nix` | knownKinds from den.schema |
| `modules/aspects/defaults.nix` | Remove entityIncludes.default |
| `modules/aspects/provides/os-class.nix` | Register as den.aspects, remove entityIncludes |
| `modules/aspects/provides/os-user.nix` | Register as den.aspects, remove entityIncludes |
| `modules/aspects/provides/wsl.nix` | Move to policy.aspects on host-to-wsl-host |
| `modules/aspects/provides/home-manager.nix` | Remove entityIncludes.home |
| `modules/compat/ctx-shim.nix` | Forward to den.aspects instead of entityIncludes |
| `modules/outputs/flakeSystemOutputs.nix` | Remove entityIncludes reads/writes |
| `modules/outputs/hmConfigurations.nix` | Remove entityIncludes.flake-hm |
| `modules/outputs/osConfigurations.nix` | Remove entityIncludes.flake-os |
| `modules/policies/flake.nix` | Add isolateFanOut = true on system output policies |
| `nix/nixModule/default.nix` | Remove entities.nix import |
| `modules/context/has-aspect.nix` | Update error message |
| ~45 files under `templates/ci/modules/features/` | Migrate entityIncludes |
| ~6 files under `templates/{default,noflake,...}/` | Same |
| `templates/flake-parts-modules/modules/den.nix` | Same |
| `templates/flake-parts-modules/modules/perSystem-forward.nix` | Same |

---

## Task 0: Self-provides into resolveEntity

**Goal:** Move entity self-provide functions from module files into resolveEntity. Delete the now-redundant module files.

**Files:**
- Modify: `nix/lib/resolve-entity.nix`
- Delete: `modules/context/host.nix`, `modules/context/user.nix`
- Modify: `modules/aspects/defaults.nix` (remove entityIncludes.default line)
- Modify: `modules/aspects/provides/home-manager.nix` (remove entityIncludes.home line)
- Test: existing tests — verify unchanged behavior

**Acceptance Criteria:**
- [ ] resolveEntity generates self-provide for host entities: `({ host }: host.aspect)`
- [ ] resolveEntity generates self-provide for user entities: `({ host, user }: user.aspect)`
- [ ] resolveEntity generates self-provide for home entities: `({ home }: home.aspect)`
- [ ] resolveEntity generates self-provide for default: `den.default`
- [ ] `modules/context/host.nix` and `user.nix` deleted
- [ ] `emitSelfProvide` in resolveChildren is now a functional no-op (no `provides.${name}` to trigger on)
- [ ] 633/633 tests pass

**Verify:** `nix develop -c just fmt && just ci`

**Steps:**

- [ ] **Step 1: Rewrite resolve-entity.nix**

The self-provide functions must be parametric (with named args), not raw values. This is critical — we proved during direct-ref-aspects that raw attrsets cause identity/ordering issues in the pipeline.

```nix
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx.handlers) constantHandler;

  resolveEntity =
    name: ctx:
    let
      scopeHandlers = constantHandler ctx;
      # Self-provide: parametric function matching the old context module pattern.
      # Must use named args so the pipeline resolves through scope handlers.
      entity = ctx.${name} or null;
      hasAspect = entity != null && entity ? aspect;
      selfProvide =
        if name == "default" && den ? default then
          [ den.default ]
        else if hasAspect then
          let
            # Build function with same named-arg signature as ctx
            fn = c: c.${name}.aspect;
            args = builtins.mapAttrs (_: _: true) ctx;
          in
          [ { __fn = fn; __args = args; name = "<self:${name}>"; meta = {}; includes = []; } ]
        else
          [ ];
      entityIncludes = den.entityIncludes.${name} or [ ];
      entityProvides = den.entityProvides.${name} or { };
    in
    {
      inherit name;
      meta = {
        handleWith = null;
        excludes = [ ];
        provider = [ ];
        into = null;
      };
      rootIncludes = selfProvide ++ entityIncludes;
      provides = entityProvides;
      includes = [ ];
      __ctxStage = name;
      __scopeHandlers = scopeHandlers;
    };
in
resolveEntity
```

Note: this uses approach B (parametric `__fn`/`__args` wrapper). The wrapper is a plain attrset (not a function), so `wrapChild` in the include handler returns it unchanged via the `else child` branch (line 79). Then `aspectToEffect` sees `__args != {}` (`isParametric = true`) and resolves the named args from scope handlers — the standard parametric resolution path.

If tests fail with identity/ordering issues, fall back to approach C: add a new `"emit-self"` effect. Sketch:
```nix
# Handler in aspect.nix or a new file:
emitSelfHandler = {
  "emit-self" = { param, state }:
    let kind = param.kind; in
    # Resolve ctx.${kind}.aspect from scope handlers at pipeline time
    { resume = fx.bind.fn { ${kind} = true; } (c: c.${kind}.aspect);
      inherit state; };
};
# resolveEntity emits: fx.send "emit-self" { kind = name; }
# Pipeline handles it with scope handlers in place — avoids capturing entity at resolution time.
```
This avoids the wrapper format entirely by resolving through scope handlers at pipeline time, side-stepping identity issues. We don't expect to need it.

- [ ] **Step 2: Delete host.nix and user.nix**

```bash
rm modules/context/host.nix modules/context/user.nix
```

These are auto-discovered by the module system — no import to remove.

- [ ] **Step 3: Remove self-provide from defaults.nix**

At `modules/aspects/defaults.nix`, remove lines 7-9:

```nix
{ den, lib, ... }:
{
  options.den.default = lib.mkOption {
    description = "Default aspect";
    type = den.lib.aspects.types.aspectType;
  };
}
```

- [ ] **Step 4: Remove self-provide from home-manager.nix**

At `modules/aspects/provides/home-manager.nix` line 27, remove `den.entityIncludes.home = [ ({ home }: home.aspect) ];`.

- [ ] **Step 5: Format, test, commit**

```bash
nix develop -c just fmt && just ci
git add nix/lib/resolve-entity.nix modules/aspects/defaults.nix modules/aspects/provides/home-manager.nix
git add -u modules/context/host.nix modules/context/user.nix
git -c core.hooksPath=/dev/null commit -m "feat: self-provides in resolveEntity, delete context modules"
```

If tests fail: check the approach C fallback described in the spec before reverting. The fix is usually one targeted change, not a full revert.

---

## Task 1: Framework aspects to policy.aspects

**Goal:** Move os-class, os-user, and wsl framework aspects from entityIncludes to policy.aspects on core policies. Host-level `host-os-fwd` goes into resolveEntity includes.

**Files:**
- Modify: `modules/aspects/provides/os-class.nix`
- Modify: `modules/aspects/provides/os-user.nix`
- Modify: `modules/aspects/provides/wsl.nix`
- Modify: `nix/lib/resolve-entity.nix` (add host-os-fwd to host includes)
- Modify: `nix/lib/home-env.nix` (add user-os-fwd and os-user fwd to policy.aspects)
- Test: existing tests

**Acceptance Criteria:**
- [ ] No module writes to `den.entityIncludes.host`, `den.entityIncludes.user`, or `den.entityIncludes."wsl-host"`
- [ ] `host-os-fwd` delivered via resolveEntity includes for host entities
- [ ] `user-os-fwd` and os-user `fwd` delivered via policy.aspects on host→user policies
- [ ] wsl aspect delivered via policy.aspects on host-to-wsl-host
- [ ] os-class, os-user, wsl aspects registered in `den.aspects`
- [ ] 633/633 tests pass

**Verify:** `nix develop -c just fmt && just ci`

**Steps:**

- [ ] **Step 1: Register os-class aspects in den.aspects and remove entityIncludes**

At `modules/aspects/provides/os-class.nix`, register `host-os-fwd` and `user-os-fwd` as `den.aspects` entries and remove the entityIncludes writes:

```nix
in
{
  den.aspects.os-host-fwd = host-os-fwd;
  den.aspects.os-user-fwd = user-os-fwd;

  den.classes.os.description = "Convenience class forwarding to both nixos and darwin";
}
```

- [ ] **Step 2: Register os-user aspect and remove entityIncludes**

At `modules/aspects/provides/os-user.nix`, register `fwd` as a `den.aspects` entry:

```nix
in
{
  den.aspects.os-user-class-fwd = fwd;

  den.classes.user.description = "Lightweight user environment forwarding to OS users.users";
}
```

- [ ] **Step 3: Add host-os-fwd to resolveEntity includes for host entities**

In `nix/lib/resolve-entity.nix`, add `den.aspects.os-host-fwd` to the host entity's includes. Hosts are root entities with no inbound policy, so this is the only delivery path:

```nix
      hostFramework = if name == "host" then [ (den.aspects.os-host-fwd or null) ] else [ ];
      # Filter nulls in case os-class module isn't loaded
      frameworkIncludes = builtins.filter (x: x != null) hostFramework;
```

Add `frameworkIncludes` to `rootIncludes`:

```nix
      rootIncludes = selfProvide ++ frameworkIncludes ++ entityIncludes;
```

- [ ] **Step 4: Add user framework aspects to makeHomeEnv policy.aspects**

In `nix/lib/home-env.nix`, the `host-to-${ctxName}-users` policy needs `os-user-fwd` and `os-user-class-fwd`:

```nix
      policies = {
        "host-to-${ctxName}-users" = {
          from = "host";
          to = "user";
          aspects = [
            hostModule
            userForward
          ] ++ (lib.optional (den.aspects ? os-user-fwd) den.aspects.os-user-fwd)
            ++ (lib.optional (den.aspects ? os-user-class-fwd) den.aspects.os-user-class-fwd);
```

The `lib.optional` guards handle the case where os-class/os-user modules aren't loaded.

- [ ] **Step 5: Move wsl entityIncludes to policy.aspects**

At `modules/aspects/provides/wsl.nix`, the aspect function currently in entityIncludes becomes a `den.aspects` entry, and the policy carries it:

```nix
  wsl-host-aspect =
    { host }:
    {
      inherit description;
      ${host.class} = {
        imports = [ host.wsl.module ];
        wsl.enable = true;
      };
      includes = [ fwd ];
    };

in
{
  den.classes.wsl.description = "WSL support class forwarding to host OS";

  den.aspects.wsl-host-aspect = wsl-host-aspect;
  den.schema.host.imports = [ hostConf ];

  den.policies.host-to-wsl-host = {
    from = "host";
    to = "wsl-host";
    aspects = [ wsl-host-aspect ];
    resolve =
      { host, ... }:
      lib.optional (host.class == "nixos" && (host.wsl or { }).enable or false) { inherit host; };
  };

  den.schema.host.policies = [ "host-to-wsl-host" ];
}
```

- [ ] **Step 6: Format, test, commit**

```bash
nix develop -c just fmt && just ci
git add modules/aspects/provides/os-class.nix modules/aspects/provides/os-user.nix modules/aspects/provides/wsl.nix nix/lib/resolve-entity.nix nix/lib/home-env.nix
git -c core.hooksPath=/dev/null commit -m "feat: framework aspects to policy.aspects, remove entityIncludes writes"
```

---

## Task 2: Provides deprecation shim

**Goal:** Add type-level rewrite of `provides.X` keys to direct nesting, preserving user API with trace warning. This must land BEFORE test migration so `provides.to-users` patterns keep working.

**Files:**
- Modify: `nix/lib/aspects/types.nix` (aspectSubmodule provides option)
- Modify: `nix/lib/den-brackets.nix` (remove `/` → `.provides.` rewrite)
- Test: existing tests — all `provides.to-users` patterns must still work

**Acceptance Criteria:**
- [ ] `den.aspects.igloo.provides.to-users = { ... }` rewrites to `den.aspects.igloo.to-users = { ... }` with trace warning
- [ ] The `_` alias (`den.aspects.igloo._.to-users`) still works (alias of provides)
- [ ] `den-brackets.nix` no longer converts `/` to `.provides.`
- [ ] 633/633 tests pass

**Verify:** `nix develop -c just fmt && just ci`

**Steps:**

- [ ] **Step 1: Add provides deprecation rewrite in aspectSubmodule**

At `nix/lib/aspects/types.nix` in the `aspectSubmodule` function (around line 224), the `provides` option (lines 308-322) remains as-is for backward compat, but add a `config` block that rewrites provides entries to the parent freeform type:

In the submodule definition at line 226, add after the `options` block:

```nix
config = let
  providesEntries = builtins.removeAttrs (config.provides or {}) ["_module"];
  warnedEntries = lib.mapAttrs (k: v:
    lib.warn "den: aspect '${config.name}' uses 'provides.${k}' — migrate to direct nesting at key '${k}'"
      v
  ) providesEntries;
in lib.mkIf (providesEntries != {}) warnedEntries;
```

This config block takes each `provides.X` entry and sets it as a top-level key `X` on the freeform type, with a deprecation warning. The freeform type (`lazyAttrsOf aspectContentType`) accepts these entries.

Note: this approach requires careful testing. The `provides` option and freeform keys share the same submodule namespace, so writing to both `provides.X` and `X` directly would conflict. The shim must only fire when `provides.X` is set and `X` is not set directly. Add a guard:

```nix
config = let
  providesEntries = builtins.removeAttrs (config.provides or {}) ["_module"];
  nonConflicting = lib.filterAttrs (k: _: !(config ? ${k}) || k == "provides") providesEntries;
  warnedEntries = lib.mapAttrs (k: v:
    lib.warn "den: aspect '${config.name}' uses 'provides.${k}' — migrate to direct nesting at key '${k}'"
      v
  ) nonConflicting;
in lib.mkIf (nonConflicting != {}) warnedEntries;
```

**Infinite recursion risk:** Self-referential config blocks in submodules with freeformType can cause infinite recursion if the freeform merge re-evaluates `config.provides`. If this happens, implement the rewrite in the type's `merge` function (`mergeWithAspectMeta` in types.nix) instead of a config block — intercept `provides` keys during merge and promote them to top-level entries before the submodule evaluates.

- [ ] **Step 2: Update den-brackets.nix**

At `nix/lib/den-brackets.nix` line 40, remove the provides rewrite. The `<igloo/to-users>` bracket syntax should resolve directly to `igloo.to-users` (the new nesting location):

```nix
# Before (line 40):
(lib.strings.replaceStrings [ "/" ] [ ".provides." ])

# After:
(lib.strings.replaceStrings [ "/" ] [ "." ])
```

Note: the `denfulTail` branch at line 26 which strips `provides` from `den.ful.*` paths should be kept for now — `den.ful` lookups may still go through `provides` during the transition. Remove it in Task 5 when provides is fully eliminated.

- [ ] **Step 3: Format, test, commit**

```bash
nix develop -c just fmt && just ci
git add nix/lib/aspects/types.nix nix/lib/den-brackets.nix
git -c core.hooksPath=/dev/null commit -m "feat: provides deprecation shim, rewrite to direct nesting"
```

---

## Task 3: Migrate test entityIncludes

**Goal:** Convert all `den.entityIncludes` writes in test/template files. This is the bulk migration — ~45 CI test files + ~8 template files.

**Files:**
- Modify: ~45 files under `templates/ci/modules/features/`
- Modify: ~6 files under `templates/{default,noflake,nvf-standalone,flake-parts-modules,microvm}/`
- Test: 633/633 tests pass

**Acceptance Criteria:**
- [ ] No test/template file writes to `den.entityIncludes` or `den.entityProvides`
- [ ] All entityIncludes patterns converted per migration rules below
- [ ] 633/633 tests pass

**Verify:** `nix develop -c just fmt && just ci && just ci-deep`

**Migration rules:**

| Pattern | Migration |
|---------|-----------|
| `den.entityIncludes.X = [ ]` (empty, existence only) | Delete entirely — entity existence no longer gated |
| `den.entityIncludes.user = [ den.provides.mutual-provider ]` | `den.policies.host-to-hm-users.aspects = [ den.provides.mutual-provider ];` |
| `den.entityIncludes.X = [ fn ]` (custom kind) | Register kind with `den.schema.X = {};` and put fn on the relevant policy's aspects, OR add fn to the aspect's includes directly |
| `den.entityIncludes.X = [ den.default ]` | Delete — resolveEntity handles default self-provide |

**Steps:**

- [ ] **Step 1: Find all entityIncludes writes in test files**

```bash
grep -rn "entityIncludes" templates/ --include="*.nix" | grep -v "node_modules"
```

- [ ] **Step 2: Migrate empty existence registrations**

Delete all `den.entityIncludes.X = [ ];` lines. These were only for kind registration — entity resolution no longer checks existence.

Files with empty registrations: `policy-activation.nix`, `policy-inspect.nix`, `policy-as-field.nix`, and others matching `entityIncludes.X = [ ]`.

- [ ] **Step 3: Migrate mutual-provider patterns**

The most common pattern. Replace:
```nix
den.entityIncludes.user = [ den.provides.mutual-provider ];
```
With:
```nix
den.policies.host-to-hm-users.aspects = [ den.provides.mutual-provider ];
```

Files: `user-host-mutual-config.nix`, `define-user.nix`, `host-options.nix`, `auto-parametric.nix`, `has-aspect.nix`, `conditional-config.nix`, `perUser-perHost.nix`, and others.

- [ ] **Step 4: Migrate custom entity kind registrations**

For test-specific entity kinds (e.g., `entityIncludes.greet = [...]`), convert to aspect includes or policy aspects depending on the test's structure. Each test needs individual analysis — read the test to understand what entity kind it creates and which transition reaches it.

- [ ] **Step 5: Migrate non-CI templates**

Update `templates/default/`, `templates/noflake/`, `templates/flake-parts-modules/`, and any other templates that reference entityIncludes.

- [ ] **Step 6: Verify no entityIncludes references remain in templates**

```bash
grep -rn "entityIncludes\|entityProvides" templates/ --include="*.nix"
```

Should return zero matches.

- [ ] **Step 7: Format, test, commit**

```bash
nix develop -c just fmt && just ci && just ci-deep
git add templates/
git -c core.hooksPath=/dev/null commit -m "refactor: migrate all test entityIncludes to policy.aspects and direct includes"
```

---

## Task 4: Delete entityIncludes/entityProvides infrastructure

**Goal:** Delete the option declarations, update all references to use den.schema.

**Files:**
- Delete: `nix/nixModule/entities.nix`
- Modify: `nix/nixModule/default.nix` (remove import)
- Modify: `modules/options.nix` (knownKinds from den.schema)
- Modify: `modules/context/has-aspect.nix` (error message)
- Modify: `modules/compat/ctx-shim.nix` (forward to den.aspects)
- Modify: `modules/outputs/flakeSystemOutputs.nix` (remove entityIncludes reads/writes)
- Modify: `modules/outputs/hmConfigurations.nix` (remove entityIncludes.flake-hm)
- Modify: `modules/outputs/osConfigurations.nix` (remove entityIncludes.flake-os)
- Modify: `nix/lib/resolve-entity.nix` (remove entityIncludes/entityProvides reading)
- Test: existing tests

**Acceptance Criteria:**
- [ ] `den.entityIncludes` option no longer exists
- [ ] `den.entityProvides` option no longer exists
- [ ] `knownKinds` derived from `den.schema`
- [ ] resolveEntity no longer reads entityIncludes or entityProvides
- [ ] 633/633 tests pass

**Verify:** `nix develop -c just fmt && just ci`

**Steps:**

- [ ] **Step 1: Delete entities.nix and remove import**

```bash
rm nix/nixModule/entities.nix
```

At `nix/nixModule/default.nix` line 12, remove `./entities.nix` from the imports list.

- [ ] **Step 2: Update options.nix**

At line 20, derive knownKinds from den.schema:
```nix
schemaKinds = builtins.filter (n: n != "conf" && n != "aspect" && !(lib.hasPrefix "_" n))
  (builtins.attrNames (den.schema or { }));
knownKinds = schemaKinds;
```

At line 118, update entity guard:
```nix
if builtins.elem kind schemaKinds then
```

- [ ] **Step 3: Update has-aspect.nix error message**

At line 53, change:
```nix
"(no matching den.entityIncludes.<kind> defined)."
```
To:
```nix
"(no matching den.schema.<kind> defined)."
```

- [ ] **Step 4: Update ctx-shim.nix**

Forward `den.ctx.*` to `den.aspects` instead of `den.entityIncludes`:

```nix
# Compatibility shim: forwards den.ctx.* to den.aspects
# with deprecation warnings.
{
  den,
  lib,
  config,
  ...
}:
let
  ctxSubmodule = lib.types.submodule {
    imports = den.lib.aspects.types.aspectType.getSubModules;
    options.into = lib.mkOption {
      description = "DEPRECATED: use den.policies instead.";
      type = lib.types.nullOr lib.types.raw;
      default = null;
    };
  };
in
{
  options.den.ctx = lib.mkOption {
    description = "DEPRECATED: use den.aspects instead.";
    default = { };
    type = lib.types.lazyAttrsOf ctxSubmodule;
  };

  config.den.aspects = lib.mkMerge (
    lib.mapAttrsToList (
      name: value:
      let
        stageValue = builtins.removeAttrs value [
          "into"
          "_module"
        ];
      in
      {
        "ctx:${name}" = lib.warn "den.ctx.${name} is deprecated — use den.aspects" stageValue;
      }
    ) (builtins.removeAttrs config.den.ctx [ "_module" ])
  );
}
```

- [ ] **Step 5: Update flakeSystemOutputs.nix**

Remove entityIncludes reads (line 20-26) — `source` is always `lib.head aspect-chain`:

```nix
# Before:
entityIncs = den.entityIncludes."flake-${output}" or [ ];
hasEntityContent = entityIncs != [ ];
source = if hasEntityContent then den.lib.resolveEntity "flake-${output}" { inherit system; } else lib.head aspect-chain;

# After:
source = lib.head aspect-chain;
```

Remove entityIncludes writes (lines 63-75).

- [ ] **Step 6: Remove entityIncludes from hmConfigurations.nix and osConfigurations.nix**

At `hmConfigurations.nix` line 23, remove `den.entityIncludes.flake-hm = [ ];`.
At `osConfigurations.nix` line 25, remove `den.entityIncludes.flake-os = [ ];`.

- [ ] **Step 7: Remove entityIncludes/entityProvides from resolveEntity**

In `nix/lib/resolve-entity.nix`, remove the `entityIncludes` and `entityProvides` reading. `rootIncludes` now only has selfProvide + frameworkIncludes. `provides` is empty:

```nix
rootIncludes = selfProvide ++ frameworkIncludes;
provides = { };
```

- [ ] **Step 8: Format, test, commit**

```bash
nix develop -c just fmt && just ci
git add -u nix/nixModule/entities.nix nix/nixModule/default.nix modules/options.nix modules/context/has-aspect.nix modules/compat/ctx-shim.nix modules/outputs/flakeSystemOutputs.nix modules/outputs/hmConfigurations.nix modules/outputs/osConfigurations.nix nix/lib/resolve-entity.nix
git -c core.hooksPath=/dev/null commit -m "feat: delete entityIncludes/entityProvides, schema-based entity guard"
```

---

## Task 5: Remove rootIncludes and provides pipeline machinery

**Goal:** Delete rootIncludes phase, emitSelfProvide, mkPositionalInclude, mkNamedInclude, emitCrossProvider, crossProvider from the pipeline. Remove provides and rootIncludes from structuralKeysSet.

**Files:**
- Modify: `nix/lib/aspects/fx/aspect.nix` (structuralKeysSet, resolveChildren, delete emitSelfProvide/mkPositionalInclude/mkNamedInclude)
- Modify: `nix/lib/aspects/fx/handlers/transition.nix` (delete emitCrossProvider, remove crossProvider from resolveTransition)
- Test: existing tests

**Acceptance Criteria:**
- [ ] `structuralKeysSet` has no `rootIncludes` or `provides` entries
- [ ] `resolveChildren` ordering: transitions → includes (no selfProvide, no rootIncludes)
- [ ] `emitSelfProvide`, `mkPositionalInclude`, `mkNamedInclude` deleted from aspect.nix
- [ ] `emitCrossProvider` deleted from transition.nix
- [ ] `crossProvider` / `emitCross` removed from resolveTransition
- [ ] 633/633 tests pass

**Verify:** `nix develop -c just fmt && just ci`

**Steps:**

- [ ] **Step 1: Remove rootIncludes and provides from structuralKeysSet**

At `nix/lib/aspects/fx/aspect.nix` lines 17-18, delete `"rootIncludes"` and `"provides"` from the list.

- [ ] **Step 2: Simplify resolveChildren**

Replace the pipeline at lines 652-668:

```nix
# Before:
rootIncs = aspect.rootIncludes or [ ];
childResolution = fx.bind (builtins.seq _ (emitSelfProvide aspect)) (
  selfProvResults:
  fx.bind (emitIncludes emitCtx rootIncs) (
    rootResults:
    fx.bind (emitTransitions aspect) (
      transitionResults:
      fx.bind (emitIncludes emitCtx (aspect.includes or [ ])) (
        children: fx.pure (selfProvResults ++ rootResults ++ transitionResults ++ children)

# After:
childResolution = fx.bind (builtins.seq _ (emitTransitions aspect)) (
  transitionResults:
  fx.bind (emitIncludes emitCtx (aspect.includes or [ ])) (
    children: fx.pure (transitionResults ++ children)
```

Also remove the `providesKeys` trace warning block (lines 642-647) since provides is handled by the type-level shim.

- [ ] **Step 3: Delete emitSelfProvide, mkPositionalInclude, mkNamedInclude**

Delete the following functions from `aspect.nix`:
- `mkPositionalInclude` (lines 512-541)
- `mkNamedInclude` (lines 543-571)
- `emitSelfProvide` (lines 573-623)

Remove them from the export block at the bottom of the file.

- [ ] **Step 4: Delete emitCrossProvider from transition.nix**

Delete the `emitCrossProvider` function (lines 125-167).

- [ ] **Step 5: Remove crossProvider from resolveTransition**

At lines 241-245, remove:
```nix
sourceProvides = sourceAspect.provides or { };
crossProvider = sourceProvides.${targetKey} or null;
emitCross = emitCrossProvider { inherit crossProvider sourceAspect targetKey; };
```

At line 314, where `emitCross` is called after resolving the target, remove the cross-provider emission:
```nix
# Before:
_: fx.bind withTarget (targetResults: emitCross scopedCtx scopeHandlers ctxNames targetResults)

# After:
_: withTarget
```

- [ ] **Step 6: Remove denfulTail provides-stripping from den-brackets.nix**

At `nix/lib/den-brackets.nix` line 26, remove the provides path stripping now that provides is fully eliminated:

```nix
# Before:
denfulTail = if tail != [ ] && lib.head tail == "provides" then lib.tail tail else tail;

# After:
denfulTail = tail;
```

- [ ] **Step 7: Format, test, commit**

```bash
nix develop -c just fmt && just ci
git add nix/lib/aspects/fx/aspect.nix nix/lib/aspects/fx/handlers/transition.nix nix/lib/den-brackets.nix
git -c core.hooksPath=/dev/null commit -m "refactor: remove rootIncludes, provides pipeline machinery"
```

---

## Task 6: Extract runSubPipeline combinator

**Goal:** Extract a thin `runSubPipeline` function that standardizes fxFullResolve → state materialization. Update three call sites.

**Files:**
- Modify: `nix/lib/aspects/fx/pipeline.nix` (add runSubPipeline)
- Modify: `nix/lib/aspects/fx/handlers/transition.nix` (resolveFanOut, resolveSiblingTransition)
- Modify: `nix/lib/aspects/fx/handlers/forward.nix` (forwardHandler)
- Test: existing tests

**Acceptance Criteria:**
- [ ] `runSubPipeline` exported from `den.lib.aspects.fx.pipeline`
- [ ] `resolveFanOut` uses `runSubPipeline`
- [ ] `resolveSiblingTransition` uses `runSubPipeline`
- [ ] `forwardHandler` uses `runSubPipeline`
- [ ] 633/633 tests pass

**Verify:** `nix develop -c just fmt && just ci`

**Steps:**

- [ ] **Step 1: Add runSubPipeline to pipeline.nix**

After `fxFullResolve` (around line 165):

```nix
  # Thin wrapper: runs sub-pipeline, materializes state thunks.
  # Each call site does its own post-processing.
  runSubPipeline =
    {
      class,
      self,
      ctx,
    }:
    let
      result = fxFullResolve { inherit class self ctx; };
    in
    {
      imports = result.state.imports null;
      traits = result.state.traits null;
      provideTo = (result.state.provideTo or (_: [ ])) null;
    };
```

Export it alongside `fxFullResolve`.

- [ ] **Step 2: Update resolveFanOut in transition.nix**

```nix
  resolveFanOut =
    {
      effectiveTarget,
      scopedCtx,
      scopeHandlers,
      ctxNames,
    }:
    innerResults:
    let
      tagged = effectiveTarget // {
        __scopeHandlers = scopeHandlers;
        __ctxId = ctxNames;
      };
      sub = den.lib.aspects.fx.pipeline.runSubPipeline {
        class = ""; # class no longer needed — was only for the flake check
        self = tagged;
        ctx = scopedCtx;
      };
      mergeImports = fx.effects.state.modify (st: st // { imports = x: (st.imports x) ++ sub.imports; });
    in
    fx.bind mergeImports (_: fx.pure innerResults);
```

Note: `class` was only used for the `targetClass == "flake"` check which is removed in Task 7. Pass empty string or the actual class if needed for other purposes. Check if `mkPipeline` requires it — it does (line 130: `class`), so pass `targetClass` through. Read the current value from the state or parameter.

Actually, `resolveFanOut` currently receives `targetClass`. Keep passing it:

```nix
      sub = den.lib.aspects.fx.pipeline.runSubPipeline {
        class = targetClass;
        self = tagged;
        ctx = scopedCtx;
      };
```

- [ ] **Step 3: Update resolveSiblingTransition in transition.nix**

```nix
          stageAspect = den.lib.resolveEntity transition.routing.from scopedCtx;
          sub = den.lib.aspects.fx.pipeline.runSubPipeline {
            class = targetClass;
            self = stageAspect;
            ctx = scopedCtx;
          };
          traits = sub.traits;
```

Replace the direct `fxFullResolve` call and `subResult.state.traits null` materialization.

- [ ] **Step 4: Update forwardHandler in forward.nix**

```nix
        sub = den.lib.aspects.fx.pipeline.runSubPipeline {
          class = spec.fromClass;
          self = normalizedSource;
          ctx = resolveCtx;
        };

        rawSourceModule = { imports = sub.imports; };
        sourceModule = spec.mapModule rawSourceModule;
        forwardAspect = buildForwardAspect spec sourceModule;

        subProvideToThunk = sub.provideTo;
```

Replace `fxFullResolve` call and state materialization. Note: `provideTo` is now a plain list (already materialized), not a thunk. Update the state splice:

```nix
        state = state // {
          provideTo = _: ((state.provideTo or (_: [ ])) null) ++ subProvideToThunk;
        };
```

(`subProvideToThunk` was `(sourceResult.state.provideTo or (_: [])) null` before; now it's just `sub.provideTo`.)

- [ ] **Step 5: Format, test, commit**

```bash
nix develop -c just fmt && just ci
git add nix/lib/aspects/fx/pipeline.nix nix/lib/aspects/fx/handlers/transition.nix nix/lib/aspects/fx/handlers/forward.nix
git -c core.hooksPath=/dev/null commit -m "refactor: extract runSubPipeline combinator"
```

---

## Task 7: Add isolateFanOut to policies

**Goal:** Replace `isFanOut && targetClass == "flake"` hardcode with `policy.isolateFanOut` flag.

**Files:**
- Modify: `nix/lib/policy-types.nix` (add isolateFanOut option)
- Modify: `nix/lib/aspects/fx/handlers/policy-dispatch.nix` (propagate to routing)
- Modify: `nix/lib/aspects/fx/handlers/transition.nix` (read from routing)
- Modify: `modules/policies/flake.nix` (set isolateFanOut = true)
- Test: existing tests

**Acceptance Criteria:**
- [ ] `policy.isolateFanOut` option exists (bool, default false)
- [ ] `isolateFanOut` propagated through routing in policy-dispatch.nix
- [ ] resolveTransition uses `transition.routing.isolateFanOut or false` instead of `targetClass == "flake"`
- [ ] Flake system output policies have `isolateFanOut = true`
- [ ] 633/633 tests pass

**Verify:** `nix develop -c just fmt && just ci`

**Steps:**

- [ ] **Step 1: Add option to policy-types.nix**

After the `_core` option:

```nix
      isolateFanOut = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Run each fan-out context in an isolated sub-pipeline instead of shared state.";
      };
```

- [ ] **Step 2: Propagate in policy-dispatch.nix**

At line 59, add `isolateFanOut` to the routing record:

```nix
                routing = {
                  inherit (policy) from to;
                  inherit targetKey;
                  policyName = name;
                  aspects = policy.aspects or [ ];
                  isolateFanOut = policy.isolateFanOut or false;
                };
```

- [ ] **Step 3: Update resolveTransition in transition.nix**

Replace the hardcoded check:

```nix
# Before:
if isFanOut && targetClass == "flake" then

# After:
if isFanOut && (transition.routing.isolateFanOut or false) then
```

- [ ] **Step 4: Set flag on flake policies**

At `modules/policies/flake.nix`, add `isolateFanOut = true` to the `systemOutputPolicies` template:

```nix
    value = {
      _core = true;
      from = "flake-system";
      to = "flake-${output}";
      aspects = [ den.aspects."flake-${output}" ];
      isolateFanOut = true;
      resolve = ...
```

- [ ] **Step 5: Remove targetClass from resolveFanOut signature**

After `isolateFanOut` replaces the class check, `resolveFanOut` no longer needs `targetClass` in its parameter set (unless `runSubPipeline` still passes it). Check whether `class` is used for anything else in the sub-pipeline — it is (passed to `mkPipeline`), so keep it but source it from state rather than the hardcoded `"flake"` assumption. Actually, `targetClass` is still available in `resolveTransition`'s scope — just keep passing it through. No change needed here.

- [ ] **Step 6: Format, test, commit**

```bash
nix develop -c just fmt && just ci
git add nix/lib/policy-types.nix nix/lib/aspects/fx/handlers/policy-dispatch.nix nix/lib/aspects/fx/handlers/transition.nix modules/policies/flake.nix
git -c core.hooksPath=/dev/null commit -m "feat: policy.isolateFanOut replaces hardcoded flake fan-out"
```

---

## Dependency Graph

```
Task 0 (self-provides into resolveEntity)
  ↓
Task 1 (framework aspects to policy.aspects) ← depends on Task 0
  ↓
Task 2 (provides deprecation shim) ← independent, but cleaner after Task 1
  ↓
Task 3 (migrate test entityIncludes) ← depends on Tasks 1 + 2
  ↓
Task 4 (delete entityIncludes infrastructure) ← depends on Task 3
  ↓
Task 5 (remove rootIncludes + provides machinery) ← depends on Task 4
  ↓
Task 6 (extract runSubPipeline) ← independent of Tasks 0-5, cleaner after
  ↓
Task 7 (add isolateFanOut) ← depends on Task 6
```

Tasks 6-7 are independent of the entity migration and can be done in any order after Task 5.

---

## Notes for Implementers

### Key patterns
- `den.entityIncludes.X = [ fn ]` where fn is self-provide → delete (resolveEntity handles it)
- `den.entityIncludes.X = [ fwd ]` where fwd is framework → `policy.aspects = [ fwd ]` on relevant policy
- `den.entityIncludes.X = []` (existence registration) → delete entirely
- `den.aspects.*.provides.X = { ... }` → handled by type-level deprecation shim (no manual migration needed)

### Nix conventions
- `nix develop -c just fmt` before committing
- `git -c core.hooksPath=/dev/null commit`
- Do NOT add Co-Authored-By trailers or commit docs/superpowers/ files
- One agent at a time, no parallel execution
- Stage specific files by name, never `git add -A` or `git add .`

### Test commands
- `just ci` for quick (633 tests), `just ci-deep` for verbose errors
- `just ci-deep <suite>` for focused debugging

### Fallback for Task 0
If the `__fn`/`__args` parametric wrapper approach fails with identity/ordering issues (as we saw during direct-ref-aspects), the fallback is approach C: add a new `"emit-self"` effect to the pipeline that resolves `ctx.${kind}.aspect` at pipeline time via scope handlers. This avoids the wrapper format entirely but requires a new handler.
