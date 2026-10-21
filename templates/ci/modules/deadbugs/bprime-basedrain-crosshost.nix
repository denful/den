# B′ cross-host peer-config divergence witness (§A #8/#2/#7).
#
# `hostConfigs` (re-entry B′, resolve.nix) builds each peer host's full nixos
# config for cross-host config-dependent pipe-thunk resolution (assemble-pipes
# resolveEntry reads `config = hostConfigs.${sourceScopeId}`). Pre-fix B′ built
# those configs over the RAW scopeContexts (§A #8) and RAW (undrained) class
# imports (§A #2/#7) — so a peer whose config CONSUMES a pipe value (or
# depends on a deferred include) diverged from its real instantiate output
# (variant B): the pipe value was never injected / the include never drained, so
# the peer config threw `attribute 'feat' missing` instead of resolving.
#
# Witness shape (the §A probe template, minimised to the natural host topology):
#   - a pipe-consuming peer aspect `needs-feat.nixos = { feat, ... }:
#     { networking.domain = builtins.head feat; }` — reads the `feat` quirk value
#     from its context. `feat` is a host-scope pipe (pipe.for → [ host.name ]),
#     resolved by assemblePipes, NOT present in raw scopeContexts;
#   - a cross-host `collectAll` config-thunk `host-marks = { config, ... }:
#     [ "d-${config.networking.domain}" ]` reading each peer's config — this is
#     what forces hostConfigs (B′) to build the peer configs.
#
# Only igloo COLLECTS (asymmetric on purpose): a mutual collectAll (both hosts
# reading each other's config) is a genuine inter-config cycle no pass can break.
# Both hosts EMIT a host-marks value, so igloo's collectAll builds BOTH configs.
#
# Before the fix: igloo's collectAll reads iceberg's `config.networking.domain`
# via hostConfigs.${iceberg} (B′), built over raw contexts → `feat` unbound →
# `feat missing`. After the fix (B′ over augmentedScopeContextsNoCfg +
# drainedForHostConfigs): the peer config matches variant B and resolves.
#
# Control: a cross-host thunk reading a NON-pipe config field (hostName, set from
# the host record) resolves under B′ regardless — isolating the pipe/deferred
# injection as the cause.
{ denTest, lib, ... }:
{
  flake.tests.deadbugs.bprime-basedrain-crosshost = {

    # Defect case: cross-host config-thunk reads a PIPE-derived config field.
    # Pre-fix this threw `feat missing`; after, it resolves to the peer's value.
    test-crosshost-thunk-reads-pipe-config = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      let
        inherit (den.lib.policy) pipe;
      in
      {
        den.quirks.feat.description = "A host-scope pipe (scalar feature value).";
        den.quirks.host-marks.description = "Cross-host config-derived marks.";

        # Every host emits its own `feat` pipe value; only igloo collects marks.
        den.policies.emit-feat = { host, ... }: [ (pipe.from "feat" [ (pipe.for (_: [ host.name ])) ]) ];
        den.policies.collect-marks = _: [
          (pipe.from "host-marks" [ (pipe.collectAll ({ host, ... }: true)) ])
        ];
        den.schema.host.includes = [ den.policies.emit-feat ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        # The pipe-CONSUMING peer aspect: reads `feat` from context (resolved by
        # assemblePipes, absent from raw scopeContexts). Sets a config field FROM
        # the pipe value — so a peer's config.networking.domain depends on it.
        den.aspects.needs-feat.nixos =
          { feat, ... }:
          {
            networking.domain = builtins.head feat;
          };
        den.aspects.igloo.includes = [
          den.aspects.needs-feat
          den.policies.collect-marks
        ];
        den.aspects.iceberg.includes = [ den.aspects.needs-feat ];

        # Each host EMITS a host-marks value = a config-thunk reading its OWN
        # pipe-derived domain. igloo's collectAll gathers them, forcing
        # hostConfigs (B′) to build each peer's config (where the defect lived).
        den.aspects.igloo.host-marks = { config, ... }: [ "d-${config.networking.domain}" ];
        den.aspects.iceberg.host-marks = { config, ... }: [ "d-${config.networking.domain}" ];

        # Consume the collected marks into igloo's config so the test reads them.
        den.aspects.igloo.nixos =
          { host-marks, lib, ... }:
          {
            networking.search = lib.sort (a: b: a < b) host-marks;
          };

        expr = {
          # igloo's own pipe-derived domain = its feat = "igloo".
          domain = igloo.networking.domain;
          # Cross-host collectAll sees BOTH peers' pipe-derived domains via B′.
          marks = igloo.networking.search;
        };
        expected = {
          domain = "igloo";
          marks = [
            "d-iceberg"
            "d-igloo"
          ];
        };
      }
    );

    # Control: cross-host config-thunk reads a NON-pipe config field (hostName,
    # set from the host record — present in raw contexts). Resolves under B′
    # regardless of the augmented-context fix — confirms the pipe injection is
    # the cause.
    test-crosshost-thunk-reads-nonpipe-config = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      let
        inherit (den.lib.policy) pipe;
      in
      {
        den.quirks.host-marks.description = "Cross-host config-derived marks.";

        den.policies.collect-marks = _: [
          (pipe.from "host-marks" [ (pipe.collectAll ({ host, ... }: true)) ])
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        # NON-pipe config field: hostName set from the host record (raw context).
        den.aspects.set-hostname.nixos =
          { host, ... }:
          {
            networking.hostName = host.name;
          };
        den.aspects.igloo.includes = [
          den.aspects.set-hostname
          den.policies.collect-marks
        ];
        den.aspects.iceberg.includes = [ den.aspects.set-hostname ];
        den.aspects.igloo.host-marks = { config, ... }: [ "n-${config.networking.hostName}" ];
        den.aspects.iceberg.host-marks = { config, ... }: [ "n-${config.networking.hostName}" ];

        den.aspects.igloo.nixos =
          { host-marks, lib, ... }:
          {
            networking.search = lib.sort (a: b: a < b) host-marks;
          };

        expr = igloo.networking.search;
        expected = [
          "n-iceberg"
          "n-igloo"
        ];
      }
    );
  };
}
