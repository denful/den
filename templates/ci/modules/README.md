# CI test modules

Every `.nix` file here is loaded by import-tree; suite names come from each file's
`flake.tests.<suite>`, never from its directory.

Tests that use only Den's public surface sit in `public/`, grouped by how directly
[Gen](https://github.com/sini/gen) covers the feature they need. A module's level is the
highest level any of its cells needs:

- `public/c1-aspects-schema/`: aspects and schema. Gen provides it directly.
- `public/c2-policies-outputs/`: policies and outputs. Gen provides the engine; Den fires it.
- `public/c3-routing-views/`: routing and views. Gen has the concept; Den composes it.
- `public/c4-den-surface/`: Den surface. Gen has no counterpart, but no kernel is needed.
- `public/c5-kernel-gaps/`: kernel machinery, or a feature Gen does not cover yet.

The other directories:

- `internal/`: tests that reach into pipeline internals. Not patterns to copy.
- `deprecated/`: tests pinning legacy behaviour.
- `deadbugs/`: one regression test per bug. It stays as the bug-report inbox and is not
  split by level.
- `test-support/`: the `denTest` wiring.

[dungeon](https://github.com/vic/dungeon) (Den on Gen) selects tests from this suite by level.
