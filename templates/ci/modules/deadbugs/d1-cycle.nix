{ denTest, ... }:
let
  # Cycle probe for the D1 fix: does a pipe-arg-deferred aspect-level include,
  # drained by a WALK inside mkDrained, re-enter the hostConfigs (B′) build?
  #
  # Shape is bprime-basedrain-crosshost's, with the peer's config content moved
  # behind a pipe-arg-deferred include. igloo's cross-host collectAll forces
  # hostConfigs, which consumes `drainedForHostConfigs` — the mkDrained
  # invocation over the hostConfigs-NULL contexts. If a walk there cycles, this
  # cell throws infinite recursion rather than failing a comparison.
  fixture =
    den:
    let
      inherit (den.lib.policy) pipe;
    in
    {
      den.quirks.feat.description = "A host-scope pipe (scalar feature value).";
      den.quirks.host-marks.description = "Cross-host config-derived marks.";

      den.policies.emit-feat = { host, ... }: [ (pipe.from "feat" [ (pipe.for (_: [ host.name ])) ]) ];
      den.policies.collect-marks = _: [
        (pipe.from "host-marks" [ (pipe.collectAll ({ host, ... }: true)) ])
      ];
      den.schema.host.includes = [ den.policies.emit-feat ];

      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.hosts.x86_64-linux.iceberg.users.alice = { };

      den.aspects.igloo.includes = [ den.policies.collect-marks ];

      den.aspects.iceberg.includes = [
        # Live control, same run, same includes list: a plain aspect-level
        # include. Its port must be present or the instrument is broken.
        den.aspects.cycle-plain
        # The D1 shape: pipe-arg deferred, nested include.
        (
          { feat, ... }:
          {
            name = "cycle-deferred-parent";
            includes = [ den.aspects.cycle-deferred-leaf ];
          }
        )
      ];
      den.aspects.cycle-plain.nixos.networking.firewall.allowedTCPPorts = [ 10190 ];
      den.aspects.cycle-deferred-leaf.nixos.networking.firewall.allowedTCPPorts = [ 10180 ];

      # Each host emits a config-dependent mark. This is what forces hostConfigs
      # (B′) to build the PEER's config — the path that reads
      # `drainedForHostConfigs`.
      den.aspects.igloo.host-marks = { config, ... }: [ "igloo" ];
      den.aspects.iceberg.host-marks =
        { config, ... }:
        let
          ports = config.networking.firewall.allowedTCPPorts;
          has = p: builtins.elem p ports;
        in
        [
          (
            "iceberg"
            + (if has 10190 then "-plain" else "")
            + (if has 10180 then "-deferred" else "")
            + (if has 19999 then "-NEGCONTROL" else "")
          )
        ];

      den.aspects.igloo.nixos =
        {
          host-marks,
          lib,
          ...
        }:
        {
          networking.search = lib.sort (a: b: a < b) host-marks;
        };
    };
in
{
  flake.tests.d1cycle = {
    # RED on stock: [ "iceberg-plain" "igloo" ] — the control fires, the
    # deferred include delivers nothing.
    # GREEN with the drain walk: [ "iceberg-plain-deferred" "igloo" ].
    test-crosshost-peer-config-from-deferred-include = denTest (
      { den, igloo, ... }:
      (fixture den)
      // {
        expr = igloo.networking.search;
        expected = [
          "iceberg-plain-deferred"
          "igloo"
        ];
      }
    );

    # Same fixture, the control arm alone: green on stock AND after, so a red
    # above is the deferred include and not the cross-host plumbing.
    test-control-plain-include-reaches-peer-config = denTest (
      { den, igloo, ... }:
      (fixture den)
      // {
        expr = builtins.any (m: builtins.match ".*-plain.*" m != null) igloo.networking.search;
        expected = true;
      }
    );

    # Negative control: the marker for a port nothing declares must never show.
    test-negcontrol-undeclared-port-absent = denTest (
      { den, igloo, ... }:
      (fixture den)
      // {
        expr = builtins.any (m: builtins.match ".*NEGCONTROL.*" m != null) igloo.networking.search;
        expected = false;
      }
    );
  };
}
