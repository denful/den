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
  };
}
