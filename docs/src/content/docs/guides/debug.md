---
title: Debug Configurations
description: Tools and techniques for debugging Den configurations.
---

## Den CI REPL

The following loads `denTest` and `den.lib` at REPL for exploration.

```console
just repl
```

This will **not** load your project definitions, for that use:

## Your Flake REPL Inspection

Load your flake and explore interactively:

```console
$ nix repl
nix-repl> :lf .
nix-repl> nixosConfigurations.igloo.config.networking.hostName
"igloo"
```

## Expose `den` for Inspection

Temporarily expose the `den` attrset as a flake output:

```nix
{ den, ... }: {
  flake.den = den;  # remove after debugging
}
```

Then in REPL:

```console
nix-repl> :lf .
nix-repl> den.aspects.igloo
nix-repl> den.hosts.x86_64-linux.igloo
nix-repl> den.policies
```

## Inspect Policies

Use `den.lib.policyInspect.inspect` to see which policies apply to an entity and where they route:

```nix
den.lib.policyInspect.inspect {
  kind = "host";
  context = { host = den.hosts.x86_64-linux.laptop; };
}
```

This returns a set of matching policies with their targets, routing type, and source/destination entity kinds.

## Trace Aspect Includes

The resolution pipeline includes built-in tracing via `den.lib.capture` and the
[den-diagram](https://github.com/denful/den-diagram) library. Capture trace data
in den, then render with den-diagram. See [Diagrams](/explanation/diagrams/) for details.

```nix
# In a REPL (with den-diagram available as `diagram`):
diagram = inputs.den-diagram.lib;
host = den.hosts.x86_64-linux.laptop;
captured = den.lib.capture.captureWithPathsWith {
  classes = [ "nixos" "homeManager" ];
  root = den.lib.resolveEntity "host" { inherit host; };
  ctx = { inherit host; };
};
g = diagram.context { entries = captured.entries; name = host.name; };
diagram.toMermaid g  # renders the full aspect graph
```

## Trace Context

Print context values during evaluation:

```nix
den.aspects.laptop.includes = [
  ({ host, ... }@ctx: builtins.trace ctx {
    nixos.networking.hostName = host.hostName;
  })
];
```

## Break into REPL

Drop into a REPL at any evaluation point:

```nix
den.aspects.laptop.includes = [
  ({ host, ... }@ctx: builtins.break ctx {
    nixos = { };
  })
];
```

## Manually Resolve an Aspect

Note: `den.lib.aspects.resolve` is internal to the pipeline. The examples below are useful
for debugging but should not be used in production configurations.

Test how an aspect resolves for a specific class:

```console
nix-repl> module = den.lib.aspects.resolve "nixos" den.aspects.laptop
nix-repl> config = (lib.evalModules { modules = [ module ]; }).config
```

For context-dependent aspects, use the host's resolved output:

```console
nix-repl> den.hosts.x86_64-linux.laptop.mainModule
```

## Inspect a Host's Main Module

```console
nix-repl> module = den.hosts.x86_64-linux.igloo.mainModule
nix-repl> cfg = (lib.nixosSystem { modules = [ module ]; }).config
nix-repl> cfg.networking.hostName
```

With an entity kind above hosts (`den.schema.host.parent`), the first read of
a host's `mainModule` resolves the whole fleet, as `nixosConfigurations` does.
See [Host instantiation](/reference/output/#host-instantiation).

## Common Issues

**Duplicate values in lists**: Den deduplicates owned and static configs
from `den.default`, but parametric functions in `den.default.includes`
run at every context stage. The pipeline handles dispatch automatically
based on function argument shape — write a bare function with the context
args you need. The `den.lib.perHost`, `perUser`, and `perHome` shims still
exist but are deprecated (they warn and forward to the current binding rule);
prefer plain parametric aspects:

```nix
# Deprecated (warns): den.lib.perHost, den.lib.perUser, den.lib.perHome
# Preferred — plain parametric aspect; binds host at its scope / fans out:
({ host, ... }: { nixos.x = 1; })
```

**Missing attribute**: The context does not have the expected parameter.
Trace context keys to see what is available.

**Wrong class**: Check that `host.class` matches what you expect.
Darwin hosts have `class = "darwin"`, not `"nixos"`.

**Module not found**: Ensure the file is under `modules/` and not
prefixed with `_` (excluded by import-tree).

