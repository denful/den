---

## name: den-debugging description: Systematic debugging workflow for den/nix issues. Use when encountering bug reports, test failures, regressions, or unexpected behavior in den's aspect pipeline, type system, or fx handlers. Also use when a user shares an error or describes broken behavior in their den config. Trigger on phrases like "bug report", "regression", "broken", "doesn't work", "used to work", "last-win", "not merging", "not included", "wrong behavior".

# Den Debugging Workflow

A structured approach to reproducing, isolating, and fixing bugs in den. The core loop is: **understand the report, read the code path, write a failing test, confirm the failure, fix, confirm the fix, check for regressions.**

This workflow exists because den's fx pipeline has layered abstractions (content wrappers, type merges, effect handlers, key classification) where bugs often manifest far from their root cause. Writing a test first anchors your understanding before you touch implementation code.

## Phase 1: Understand the Bug Report

Before reading any code, extract the concrete claims from the report:

- **What the user did** — the nix expressions they wrote, the API surface they used
- **What they expected** — the behavior they consider correct
- **What actually happened** — the observed result (error, wrong value, missing config)
- **What works** — any workaround or alternative path that succeeds (this narrows the search)

If the report contrasts two API paths (e.g., old syntax works but new syntax doesn't), that contrast is your most valuable clue — it tells you exactly where the code paths diverge.

## Phase 2: Trace the Code Path

Read the relevant source files to understand the mechanism. Don't guess — follow the actual code path from the user's nix expression to the pipeline output.

Refer to the entry point table in `CLAUDE.md`'s "Debugging and tracing" section for a mapping of symptoms to source files and specific tracing points in the pipeline handlers.

Use the Explore agent for broad searches when you're unsure which files are involved. Use direct Grep/Read for targeted lookups when you know the function name.

## Phase 3: Write a Failing Test

Write a minimal test that reproduces the bug **before** attempting any fix. This is non-negotiable — it prevents you from "fixing" something that was never broken, and it catches regressions immediately.

### Test location and structure

Tests live in `templates/ci/modules/features/`. Bug regression tests go in `deadbugs/` and follow the naming convention `issue-NNN-short-description.nix` when there's a GitHub issue, or `descriptive-name.nix` otherwise.

### Test template

```nix
# Brief description of the bug being tested.
{
  denTest,
  lib,
  ...
}:
{
  flake.tests.deadbugs.my-bug-name = {

    test-descriptive-name = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # Set up the minimal den config that triggers the bug
        den.aspects.igloo.something = { ... };

        # Assert on the evaluated NixOS config
        expr = {
          someCheck = igloo.some.config.path == "expected";
        };
        expected = {
          someCheck = true;
        };
      }
    );

  };
}
```

### Key patterns

- **`denTest` args**: `den` (the den module), `igloo` (nixosConfigurations.igloo.config), `tuxHm` (igloo.home-manager.users.tux) are the main ones.
- **Multi-file definitions**: Use `imports` with inline modules to simulate multiple files defining the same path — you can't have duplicate keys in a single nix file.
- **Namespace setup**: Users with namespaces (e.g., `den.namespace "gloom"`) must be tested using `imports = [ (inputs.den.namespace "ns" false) ]` in denTest.  Access the namespace via the module arg (`{ ns, ... }:`), not `den.aspects`.
- **Attribute existence checks**: Use `? attrName` to test presence without crashing on missing attrs.
- **Stage new files**: Run `git add <file>` before nix can evaluate new test files.

### Run the test

```bash
# Single test with trace (preferred — use just ci with dotted path)
nix develop -c just ci deadbugs.my-bug-name.test-specific-case

# Whole suite
nix develop -c just ci deadbugs.my-bug-name

# Suite with full nix-unit output
nix develop -c just ci-deep deadbugs.my-bug-name
```

Confirm the test fails with the expected symptom before proceeding.

### Working with user configs

When a user reports a bug from their own den config, **don't try to build their flake directly** — it will have unresolvable inputs, hardware-specific modules, and secrets. Instead:

1. Read the user's modules to extract the **pattern** — how they define aspects, which module args they use, how includes are structured.
2. Write a regression test in den's CI suite that mirrors that pattern.
3. For npins users: they can't use `--override-input`, and `follows.nix` local overrides (e.g., `builtins.pathExists ./den-local`) don't work in flake evaluation context because the store copy strips symlinks. Don't waste time making their flake build — the regression test is what matters.

## Phase 4: Implement the Fix

Now that you have a failing test anchoring the expected behavior:

1. **Make the minimal change** that addresses the root cause. Resist the urge to refactor surrounding code.
1. **Run your regression test** to confirm it passes.
1. **Run the existing related tests** to check you haven't broken anything:
   ```bash
   # Run a related test suite
   nix develop -c nix-unit --override-input den . --flake ./templates/ci#.tests.<related-suite>
   ```
1. **If existing tests break**, isolate which part of your change caused it. A useful technique: revert parts of the fix independently and rerun to identify the problematic change.

## Phase 5: Validate

Run the full CI suite before considering the fix complete:

```bash
# Full suite (limit to 4 workers during agent sessions)
nix develop -c just ci

# Specific suite with traces
nix develop -c just ci suite.test
```

The summary line at the end shows pass/fail counts. All tests must pass.

### Format before committing

```bash
nix develop -c just fmt
```

CI will reject unformatted code.

## Debugging Techniques

### When a fix causes regressions

Don't revert everything. Isolate which specific change broke which test:

1. Keep the test files, revert only implementation changes
1. Re-apply changes one at a time, running the broken test after each
1. Once you identify the problematic change, understand _why_ it breaks the other case before trying a different approach

### When the root cause isn't obvious

When a bug involves content wrappers, check whether the forwarded (shallow-merged) attributes match the `__contentValues`.  `aspectContentType.merge` uses `foldl' //` to build forwarded attrs — this is last-win per key.  Structural list keys (`includes`, `excludes`) are explicitly concatenated, but other overlapping keys from different modules will silently overwrite.  The pipeline uses `__contentValues` for class emission but forwarded attrs for structural keys and direct attribute access.

Look for structural markers that distinguish the working path from the broken path. In den's pipeline, common differentiators:

- `__contentValues` — present on content wrappers from `aspectContentType`, absent on sub-aspects from `emitNestedAspect` and full aspects from `aspectSubmodule`
- `__aspectChain` — tracks the definition path through nested aspects
- `__providesForwarded` — keys forwarded from `provides` onto the aspect
- `__fn` / `__args` — parametric wrappers
- `__scopeHandlers` — context propagation

### When you need to understand data flow

Add `builtins.trace` calls temporarily to see what values flow through the pipeline:

```nix
innerValue = builtins.trace "innerValue keys: ${builtins.toJSON (builtins.attrNames innerValue)}" innerValue;
```

Remove traces before committing. See `CLAUDE.md`'s "Debugging and tracing" section for the most useful tracing points in the pipeline handlers.

### Structured tracing in tests

The `denTest` harness provides a `trace` helper that resolves an aspect tree and returns its structure. Use it to inspect what the pipeline produces without modifying pipeline code:

```nix
test-trace-example = denTest (
  { den, trace, ... }:
  let t = trace "myAspect" den.aspects.myAspect;
  in {
    expr = builtins.length t.imports > 0;
    expected = true;
  }
);
```

This is useful in Phase 3 when you want to verify what the pipeline emits for a given aspect configuration.
