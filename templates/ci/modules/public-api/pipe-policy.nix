# Tests for pipe policy effects: pipe.from with transform stages.
{ denTest, lib, ... }:
{
  flake.tests.pipe-policy = {

    # pipe.filter removes entries that don't match the predicate.
    test-pipe-filter = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.firewall = {
          description = "Firewall port declarations";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.producer
            den.aspects.consumer
          ];
        };

        den.aspects.producer = {
          firewall = [
            {
              port = 80;
              proto = "tcp";
            }
            {
              port = 53;
              proto = "udp";
            }
            {
              port = 443;
              proto = "tcp";
            }
          ];
        };

        den.aspects.consumer = {
          nixos =
            { firewall, lib, ... }:
            {
              networking.hostName = lib.concatMapStringsSep "-" (f: toString f.port) firewall;
            };
        };

        den.policies.filter-tcp =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "firewall" [
              (pipe.filter (e: e.proto == "tcp"))
            ])
          ];

        den.default.includes = [ den.policies.filter-tcp ];

        # Only TCP entries survive: 80, 443.
        expr = igloo.networking.hostName;
        expected = "80-443";
      }
    );

    # pipe.transform maps each entry.
    test-pipe-transform = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.items = {
          description = "Items";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.producer
            den.aspects.consumer
          ];
        };

        den.aspects.producer = {
          items = [
            { name = "a"; }
            { name = "b"; }
          ];
        };

        den.aspects.consumer = {
          nixos =
            { items, ... }:
            {
              networking.hostName = lib.concatMapStringsSep "-" (i: i.label) items;
            };
        };

        den.policies.transform-items =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "items" [
              (pipe.transform (i: {
                label = "x-${i.name}";
              }))
            ])
          ];

        den.default.includes = [ den.policies.transform-items ];

        expr = igloo.networking.hostName;
        expected = "x-a-x-b";
      }
    );

    # pipe.append adds an entry to the pool.
    test-pipe-append = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.items = {
          description = "Items";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.producer
            den.aspects.consumer
          ];
        };

        den.aspects.producer = {
          items = [
            { name = "a"; }
          ];
        };

        den.aspects.consumer = {
          nixos =
            { items, ... }:
            {
              networking.hostName = lib.concatMapStringsSep "-" (i: i.name) items;
            };
        };

        den.policies.append-item =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "items" [
              (pipe.append { name = "z"; })
            ])
          ];

        den.default.includes = [ den.policies.append-item ];

        expr = igloo.networking.hostName;
        expected = "a-z";
      }
    );

    # pipe.fold reduces the pool to a single value.
    test-pipe-fold = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.nums = {
          description = "Numbers";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.producer
            den.aspects.consumer
          ];
        };

        den.aspects.producer = {
          nums = [
            10
            20
            30
          ];
        };

        den.aspects.consumer = {
          nixos =
            { nums, ... }:
            {
              # fold produces a single-element list with the fold result.
              networking.hostName = toString (builtins.head nums);
            };
        };

        den.policies.fold-nums =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "nums" [
              (pipe.fold (acc: n: acc + n) 0)
            ])
          ];

        den.default.includes = [ den.policies.fold-nums ];

        expr = igloo.networking.hostName;
        expected = "60";
      }
    );

    # pipe.for replaces the list entirely.
    test-pipe-for = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.items = {
          description = "Items";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.producer
            den.aspects.consumer
          ];
        };

        den.aspects.producer = {
          items = [
            { name = "a"; }
            { name = "b"; }
          ];
        };

        den.aspects.consumer = {
          nixos =
            { items, ... }:
            {
              networking.hostName = lib.concatMapStringsSep "-" (i: i.name) items;
            };
        };

        den.policies.for-items =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "items" [
              (pipe.for (vals: lib.reverseList vals))
            ])
          ];

        den.default.includes = [ den.policies.for-items ];

        expr = igloo.networking.hostName;
        expected = "b-a";
      }
    );

    # Combined stages: filter then transform in one pipe.from.
    test-pipe-combined-stages = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.items = {
          description = "Items";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.producer
            den.aspects.consumer
          ];
        };

        den.aspects.producer = {
          items = [
            {
              name = "a";
              keep = true;
            }
            {
              name = "b";
              keep = false;
            }
            {
              name = "c";
              keep = true;
            }
          ];
        };

        den.aspects.consumer = {
          nixos =
            { items, ... }:
            {
              networking.hostName = lib.concatMapStringsSep "-" (i: i.label) items;
            };
        };

        den.policies.combined =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "items" [
              (pipe.filter (i: i.keep))
              (pipe.transform (i: {
                label = lib.toUpper i.name;
              }))
            ])
          ];

        den.default.includes = [ den.policies.combined ];

        expr = igloo.networking.hostName;
        expected = "A-C";
      }
    );

    # Multiple pipe.from in one policy targeting different pipes.
    test-pipe-multiple-from = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.alpha = {
          description = "Alpha";
        };
        den.quirks.beta = {
          description = "Beta";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.producer
            den.aspects.consumer
          ];
        };

        den.aspects.producer = {
          alpha = [
            "x"
            "y"
          ];
          beta = [
            "p"
            "q"
          ];
        };

        den.aspects.consumer = {
          nixos =
            { alpha, beta, ... }:
            {
              networking.hostName = lib.concatStringsSep "--" [
                (lib.concatStringsSep "-" alpha)
                (lib.concatStringsSep "-" beta)
              ];
            };
        };

        den.policies.multi-pipe =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "alpha" [
              (pipe.append "z")
            ])
            (pipe.from "beta" [
              (pipe.filter (v: v != "q"))
            ])
          ];

        den.default.includes = [ den.policies.multi-pipe ];

        expr = igloo.networking.hostName;
        expected = "x-y-z--p";
      }
    );

    # Multiple policies targeting the same pipe — results merge.
    test-pipe-multi-policy-merge = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.items = {
          description = "Items";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.producer
            den.aspects.consumer
          ];
        };

        den.aspects.producer = {
          items = [
            { name = "a"; }
            { name = "b"; }
          ];
        };

        den.aspects.consumer = {
          nixos =
            { items, ... }:
            {
              networking.hostName = lib.concatMapStringsSep "-" (i: i.name) items;
            };
        };

        den.policies.policy-a =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "items" [
              (pipe.filter (i: i.name == "a"))
            ])
          ];

        den.policies.policy-b =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "items" [
              (pipe.filter (i: i.name == "b"))
            ])
          ];

        den.default.includes = [
          den.policies.policy-a
          den.policies.policy-b
        ];

        # Both filters run independently on the base pool, results concatenated.
        expr = igloo.networking.hostName;
        expected = "a-b";
      }
    );

    # No pipe effects — pipe data passes through unchanged.
    test-pipe-no-policy-passthrough = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.items = {
          description = "Items";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.producer
            den.aspects.consumer
          ];
        };

        den.aspects.producer = {
          items = [
            { name = "a"; }
            { name = "b"; }
          ];
        };

        den.aspects.consumer = {
          nixos =
            { items, ... }:
            {
              networking.hostName = lib.concatMapStringsSep "-" (i: i.name) items;
            };
        };

        # No policies — pipe data passes through unmodified.
        expr = igloo.networking.hostName;
        expected = "a-b";
      }
    );
    # pipe.to delivers pipe data only to the targeted aspect.
    test-pipe-to-aspect = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.secrets = {
          description = "Secret paths";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.postgres
            den.aspects.nginx-server
          ];
        };

        den.aspects.postgres = {
          nixos =
            { secrets, ... }:
            {
              networking.hostName = builtins.head secrets;
            };
        };

        den.aspects.nginx-server = {
          nixos =
            { secrets, ... }:
            {
              networking.domain = builtins.head secrets;
            };
        };

        den.policies.app-secrets =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "secrets" [
              (pipe.filter (_: false))
              (pipe.append "pg-pass")
              (pipe.to [ den.aspects.postgres ])
            ])
            (pipe.from "secrets" [
              (pipe.filter (_: false))
              (pipe.append "nginx-key")
              (pipe.to [ den.aspects.nginx-server ])
            ])
          ];

        den.default.includes = [ den.policies.app-secrets ];

        expr = {
          host = igloo.networking.hostName;
          domain = igloo.networking.domain;
        };
        expected = {
          host = "pg-pass";
          domain = "nginx-key";
        };
      }
    );

    # Two policies targeting the same aspect on the same pipe concatenate.
    test-pipe-to-same-aspect-concat = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.items = {
          description = "Items";
        };

        den.aspects.igloo = {
          includes = [ den.aspects.consumer ];
        };

        den.aspects.consumer = {
          nixos =
            { items, ... }:
            {
              networking.hostName = lib.concatStringsSep "-" items;
            };
        };

        den.policies.policy-a =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "items" [
              (pipe.filter (_: false))
              (pipe.append "x")
              (pipe.to [ den.aspects.consumer ])
            ])
          ];

        den.policies.policy-b =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "items" [
              (pipe.filter (_: false))
              (pipe.append "y")
              (pipe.to [ den.aspects.consumer ])
            ])
          ];

        den.default.includes = [
          den.policies.policy-a
          den.policies.policy-b
        ];

        # Both targeted effects concatenate for the same aspect.
        expr = igloo.networking.hostName;
        expected = "x-y";
      }
    );

    # Untargeted and targeted coexist: targeted overrides for specific aspect.
    test-pipe-to-with-untargeted = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.items = {
          description = "Items";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.producer
            den.aspects.special
            den.aspects.normal
          ];
        };

        den.aspects.producer = {
          items = [
            "a"
            "b"
          ];
        };

        # special is targeted — gets targeted data (overrides scope-wide)
        den.aspects.special = {
          nixos =
            { items, ... }:
            {
              networking.hostName = lib.concatStringsSep "-" items;
            };
        };

        # normal is NOT targeted — gets untargeted scope-wide data
        den.aspects.normal = {
          nixos =
            { items, ... }:
            {
              networking.domain = lib.concatStringsSep "-" items;
            };
        };

        den.policies.mixed-policy =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            # Untargeted: append "c" to all
            (pipe.from "items" [
              (pipe.append "c")
            ])
            # Targeted: special only gets filtered + appended result
            (pipe.from "items" [
              (pipe.filter (_: false))
              (pipe.append "special-only")
              (pipe.to [ den.aspects.special ])
            ])
          ];

        den.default.includes = [ den.policies.mixed-policy ];

        expr = {
          # special sees targeted data (overrides scope-wide)
          special = igloo.networking.hostName;
          # normal sees untargeted data (scope-wide)
          normal = igloo.networking.domain;
        };
        expected = {
          special = "special-only";
          normal = "a-b-c";
        };
      }
    );
    # pipe.from accepts a quirk ref (den.quirks.firewall) instead of a string.
    # The ref has a `name` field injected by the apply function.
    test-pipe-from-ref = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.firewall = {
          description = "Firewall port declarations";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.producer
            den.aspects.consumer
          ];
        };

        den.aspects.producer = {
          firewall = [
            80
            443
          ];
        };

        den.aspects.consumer = {
          nixos =
            { firewall, lib, ... }:
            {
              networking.hostName = lib.concatMapStringsSep "-" toString firewall;
            };
        };

        # Use ref syntax: den.quirks.firewall instead of string "firewall".
        den.policies.filter-high =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from den.quirks.firewall [
              (pipe.filter (p: p > 100))
            ])
          ];

        den.default.includes = [ den.policies.filter-high ];

        expr = igloo.networking.hostName;
        expected = "443";
      }
    );

    # pipe.as renames pipe output to a different quirk name.
    test-pipe-as-basic = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.source = {
          description = "Source pipe";
        };
        den.quirks.target = {
          description = "Target pipe (no native emitters)";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.producer
            den.aspects.consumer
          ];
        };

        den.aspects.producer = {
          source = [
            { name = "a"; }
            { name = "b"; }
          ];
        };

        den.aspects.consumer = {
          nixos =
            { target, ... }:
            {
              networking.hostName = lib.concatMapStringsSep "-" (i: i.name) target;
            };
        };

        den.policies.rename-pipe =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "source" [
              (pipe.as "target")
            ])
          ];

        den.default.includes = [ den.policies.rename-pipe ];

        expr = igloo.networking.hostName;
        expected = "a-b";
      }
    );

    # pipe.as with transform: data reshaped before renaming.
    test-pipe-as-with-transform = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.raw-ports = {
          description = "Raw port data";
        };
        den.quirks.firewall-rules = {
          description = "Derived firewall rules";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.producer
            den.aspects.consumer
          ];
        };

        den.aspects.producer = {
          raw-ports = [
            {
              port = 80;
              proto = "tcp";
            }
            {
              port = 443;
              proto = "tcp";
            }
          ];
        };

        den.aspects.consumer = {
          nixos =
            { firewall-rules, ... }:
            {
              networking.domain = lib.concatStringsSep "-" firewall-rules;
            };
        };

        den.policies.derive-rules =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "raw-ports" [
              (pipe.transform (p: "${p.proto}:${toString p.port}"))
              (pipe.as "firewall-rules")
            ])
          ];

        den.default.includes = [ den.policies.derive-rules ];

        expr = igloo.networking.domain;
        expected = "tcp:80-tcp:443";
      }
    );

    # pipe.as + pipe.collect: cross-host collection delivered under target name.
    test-pipe-as-with-collect = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.http-addrs = {
          description = "HTTP addresses";
        };
        den.quirks.peer-urls = {
          description = "Derived peer URLs (no native emitters)";
        };

        den.policies.collect-as-urls =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "http-addrs" [
              (pipe.collect ({ host, ... }: true))
              (pipe.transform (a: "http://${a.addr}:${toString a.port}"))
              (pipe.as "peer-urls")
            ])
          ];

        den.schema.host.includes = [ den.policies.collect-as-urls ];

        den.aspects.iceberg = {
          http-addrs = {
            addr = "10.0.0.2";
            port = 80;
          };
        };

        den.aspects.igloo = {
          includes = [ den.aspects.url-consumer ];
          http-addrs = {
            addr = "10.0.0.1";
            port = 80;
          };
        };

        den.aspects.url-consumer = {
          nixos =
            { peer-urls, lib, ... }:
            {
              networking.hostName = toString (builtins.length peer-urls);
              networking.domain = lib.concatStringsSep "," (lib.sort (a: b: a < b) peer-urls);
            };
        };

        expr = {
          count = igloo.networking.hostName;
          urls = igloo.networking.domain;
        };
        expected = {
          count = "2";
          urls = "http://10.0.0.1:80,http://10.0.0.2:80";
        };
      }
    );

    # pipe.as + pipe.to: aspect-targeted delivery under renamed pipe.
    test-pipe-as-with-to = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.raw-data = {
          description = "Raw data";
        };
        den.quirks.derived-data = {
          description = "Derived data (no native emitters)";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.producer
            den.aspects.targeted-consumer
            den.aspects.normal-consumer
          ];
        };

        den.aspects.producer = {
          raw-data = [
            "x"
            "y"
          ];
        };

        # This aspect gets derived-data via pipe.as + pipe.to.
        den.aspects.targeted-consumer = {
          nixos =
            { derived-data, ... }:
            {
              networking.hostName = lib.concatStringsSep "-" derived-data;
            };
        };

        # This aspect reads raw-data normally (unaffected by pipe.as).
        den.aspects.normal-consumer = {
          nixos =
            { raw-data, ... }:
            {
              networking.domain = lib.concatStringsSep "-" raw-data;
            };
        };

        den.policies.as-and-to =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "raw-data" [
              (pipe.transform (v: "d-${v}"))
              (pipe.as "derived-data")
              (pipe.to [ den.aspects.targeted-consumer ])
            ])
          ];

        den.default.includes = [ den.policies.as-and-to ];

        expr = {
          targeted = igloo.networking.hostName;
          normal = igloo.networking.domain;
        };
        expected = {
          # targeted-consumer gets derived-data via pipe.as + pipe.to
          targeted = "d-x-d-y";
          # normal-consumer gets raw-data unmodified
          normal = "x-y";
        };
      }
    );

    # No-emitter quirk: entirely populated by pipe.as from another pipe.
    test-pipe-as-no-emitter-quirk = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.backends = {
          description = "Backend addresses";
        };
        den.quirks.monitoring-targets = {
          description = "Monitoring targets (no native emitters)";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.web
            den.aspects.monitor
          ];
        };

        # web emits backends, never mentions monitoring-targets.
        den.aspects.web = {
          backends = [
            {
              addr = "10.0.0.1";
              port = 80;
            }
            {
              addr = "10.0.0.2";
              port = 443;
            }
          ];
        };

        # monitor consumes monitoring-targets — which has no native emitters.
        den.aspects.monitor = {
          nixos =
            { monitoring-targets, lib, ... }:
            {
              networking.domain = lib.concatStringsSep "," (lib.sort (a: b: a < b) monitoring-targets);
            };
        };

        # Policy derives monitoring-targets from backends via pipe.as.
        den.policies.backends-to-monitoring =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "backends" [
              (pipe.transform (b: "${b.addr}:${toString b.port}"))
              (pipe.as "monitoring-targets")
            ])
          ];

        den.default.includes = [ den.policies.backends-to-monitoring ];

        expr = igloo.networking.domain;
        expected = "10.0.0.1:80,10.0.0.2:443";
      }
    );

    # pipe.as targeting own pipe throws an error.
    test-pipe-as-self-error = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.items = {
          description = "Items";
        };

        den.aspects.igloo = {
          items = [ "a" ];
          nixos =
            { items, ... }:
            {
              networking.hostName = lib.concatStringsSep "-" items;
            };
        };

        den.policies.self-as =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "items" [
              (pipe.as "items")
            ])
          ];

        den.default.includes = [ den.policies.self-as ];

        expr = !(builtins.tryEval (builtins.seq igloo.networking.hostName null)).success;
        expected = true;
      }
    );
  };
}
