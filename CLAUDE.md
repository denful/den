# Den

Den is a Nix flake framework for declarative multi-entity system configuration. It sits on top of NixOS, nix-darwin, and home-manager, providing a pipeline-driven layer for organizing configuration into reusable, composable units called **aspects**.

## Repository layout

```
flake.nix / default.nix    — entry points (both delegate to nix/)
nix/                       — all library and flake-module code
  default.nix              — true root: exports flakeModule, lib, templates, etc.
  flakeModule.nix           — flake-parts module, imports all of ../modules/
  denTest.nix              — test harness (denTest helper, fixtures: igloo, tuxHm, etc.)
  lib/
    aspects/               — aspect engine: types, resolve, fx pipeline
      fx/                  — effect handlers, key classification, content utils
        handlers/          — compile-static, compile-parametric, emit-classes, bind, gate, etc.
        aspect/            — children, normalize, provide
        policy/            — policy dispatch and effects
    entities/              — host.nix, home.nix entity kind definitions
    diag/capture.nix       — trace capture (graph/rendering moved to denful/den-diagram)
  nixModule/               — den.aspects, den.policies, den.lib option declarations
modules/                   — NixOS-module-style option declarations and batteries
  options.nix              — den.hosts, den.homes, den.schema, den.classes, den.quirks
  aspects/batteries/       — built-in batteries (define-user, home-manager, hostname, etc.)
  policies/                — core and flake-level policy declarations
templates/                 — example flakes + CI test suite
  ci/                      — 133+ test files in modules/features/, deadbugs/ for regressions
  minimal/, default/, example/, noflake/, microvm/, nvf-standalone/
```

## Core concepts

- **Entities** — structural units: `host`, `user`, `home`. Declared via `den.hosts`, `den.homes`. Each has an `.aspect` entry point resolved through the pipeline.
- **Aspects** — the main content unit, declared under `den.aspects.<name>`. Attrsets whose keys are classified as class keys, nested keys, or pipe keys.
- **Classes** — output buckets (`nixos`, `darwin`, `homeManager`). Aspect keys matching registered classes emit modules into that class. Registered via `den.classes`.
- **Provides / `_`** — sub-aspect namespace on every aspect. Used for selectable includes, self-provide, and cross-entity delivery. `_` is an alias for `provides`.
- **Policies** — context-driven functions that emit typed effects (routes, includes, provides). Fire when their argument signature is satisfied by scope context.
- **Pipes / Quirks** — registered via `den.quirks`. Pipe keys in aspects register pipe effects assembled post-pipeline.
- **Scope** — context-derived identity (`"host=igloo,user=tux"`) isolating emissions per entity level. Scope tree emerges from policy-driven context expansion.

## FX pipeline

The pipeline is an algebraic effects trampoline. Every state change is an effect; pure data transforms stay as functions.

Key stages: `resolve` → `compile` (shape router) → `gate` (dedup + constraints) → `compile-static` / `compile-parametric` / `compile-forward` / `compile-conditional` → `classify` → `emit-classes` → `emitNestedAspect` → `resolve-children` → policy iteration → drain deferred.

Four aspect shapes, detected by the compiler router:

- **Static** — no special fields → `compile-static`
- **Parametric** — has `__args` → `compile-parametric` (binds scope args, re-resolves)
- **Forward** — has `meta.__forward` → `compile-forward`
- **Conditional** — has `meta.guard` → `compile-conditional`

## Development commands

```bash
# formatting (required before commits, CI rejects unformatted code)
nix develop -c just fmt

# run full CI suite
nix develop -c just ci

# run full CI suite with full nix-unit output (slow)
nix develop -c just ci-deep

# run a specific test suite
nix develop -c just ci nested-aspects

# run a specific test with traces
nix develop -c just ci nested-aspects.test-direct-nesting-basic

# run tests directly via nix-unit (more control)
nix-unit --override-input den . --flake ./templates/ci#.tests.<suite>

# check a template
nix flake check --override-input den . ./templates/<template>

# interactive repl with den loaded
just repl
```

## Testing

Tests live in `templates/ci/modules/features/`. Bug regressions go in `deadbugs/`.

Test files export `flake.tests.<suite>.<test-name>` using the `denTest` helper:

```nix
{ denTest, ... }:
{
  flake.tests.my-suite = {
    test-something = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos.networking.hostName = "test";

        expr = igloo.networking.hostName;
        expected = "test";
      }
    );
  };
}
```

Key `denTest` args: `den`, `igloo` (nixosConfigurations.igloo.config), `tuxHm` (igloo.home-manager.users.tux), `ns` (when a namespace is imported).

New test files must be `git add`'d before nix can evaluate them. Use `--override-input den .` to test against the local checkout.

## Git conventions

- Format before committing: `nix develop -c just fmt`
- Stage files explicitly by name, never `git add -A` or `git add .`
- Stage new `.nix` files before running nix eval/test (nix needs them tracked)

## Code style

- Idiomatic Nix: use `inherit` for hyphenated identifiers in scope, not quoted assignment
- Idiomatic Nix: use `lib.optional` `lib.optionals` `lib.optionalAttrs` for basic conditionals
- Idiomatic Nix: avoid `with` — prefer `inherit` to bring names into scope. `with` obscures where bindings come from and breaks tooling.
- Error messages: prefix with `den:` for traceability (e.g., `throw "den: multiple __functor definitions at ..."`)
- Internal markers: double-underscore prefixed attrs (`__contentValues`, `__aspectChain`, `__fn`) are pipeline internals. Don't add new ones without understanding the classification and structural key filtering in `key-classification.nix`.
- Commenting: comments should describe why not what, code should be self documenting as to what
- Minimal changes: fix the bug, don't refactor surroundings
- Diagnose before reverting: the fix is usually one targeted change
- After 3+ workarounds in the same area, redesign the component instead of patching further

## Claude Code skills

- **den-debugging** (`.claude/skills/den-debugging.md`) — structured workflow for reproducing, isolating, and fixing bugs. Guides through: understand report → trace code path → write failing test → fix → validate. Includes an entry point table mapping symptoms to source files.

## Diagrams (den-diagram)

Diagram rendering lives in a separate repo: [denful/den-diagram](https://github.com/denful/den-diagram). Den keeps only the capture layer (`nix/lib/diag/capture.nix`) which runs the fx pipeline with tracing handlers.

**Capture** stays in den — `den.lib.capture.*`:

- `capture`, `captureAll`, `captureWithPaths`, `captureWithPathsWith`, `captureFleet`

**Rendering** lives in den-diagram — added as `inputs.den-diagram` in templates that need it:

```nix
diagram = inputs.den-diagram.lib;

# Two-step: capture in den, render in den-diagram
captured = den.lib.capture.captureWithPathsWith {
  classes = [ "nixos" "homeManager" ];
  root = den.lib.resolveEntity "host" { inherit host; };
  ctx = { inherit host; };
};
g = diagram.context {
  entries = captured.entries;
  ctxTrace = captured.ctxTrace;
  name = host.name;
};
rendered = diagram.toMermaid g;
```

Templates using den-diagram: `diagram-demo`, `fleet-demo`. Den's core flake and CI have no den-diagram dependency.

## Debugging and tracing

For pipeline debugging, use `builtins.trace` temporarily to inspect values flowing through handlers:

```nix
innerValue = builtins.trace "keys: ${builtins.toJSON (builtins.attrNames innerValue)}" innerValue;
```

Remove all `builtins.trace` calls before committing — the pipeline code intentionally has none.

For structured pipeline tracing in tests, use the `trace` helper from `denTest`:

```nix
test-trace-example = denTest (
  { den, trace, ... }:
  let t = trace "myAspect" den.aspects.myAspect;
  in { expr = t.imports; expected = ...; }
);
```

Use `--show-trace` with `nix-unit` for full Nix evaluation stack traces on errors.

**Useful tracing points in the pipeline:**

- **Gate dedup** (`handlers/gate.nix`) — trace `dedupKey` and `isDuplicate` to see why an aspect is being skipped. The dedup key is `"${scopeId}/${identityKey}"`.
- **Emit-class collector** (`handlers/class-collector.nix`) — trace `loc` (`"${param.class}@${baseIdentity}"`) and `alreadyEmitted` to see what class modules are collected and whether dedup is suppressing entries.
- **Classification** (`handlers/classify.nix`) — trace the `classified` result to see how keys are partitioned into `classKeys`, `nestedKeys`, and `pipeKeys`.
- **Emit-classes** (`handlers/emit-classes.nix`) — trace `modules` from `unwrapContentValuesList aspect.${k}` to see what's actually being emitted for a class key.
- **Compile-static nested walk** (`handlers/compile-static.nix`) — trace `nestedToWalk` to see which nested keys are auto-walked vs suppressed.
