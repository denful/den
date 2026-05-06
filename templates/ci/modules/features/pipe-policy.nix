# Tests for pipe policy effects: pipe.from with transform stages.
{ denTest, lib, ... }:
{
  flake.tests.pipe-policy = {

    # pipe.filter removes entries that don't match the predicate.
    test-pipe-filter = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.pipes.firewall = {
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
        den.pipes.items = {
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
        den.pipes.items = {
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
        den.pipes.nums = {
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
        den.pipes.items = {
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
        den.pipes.items = {
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
        den.pipes.alpha = {
          description = "Alpha";
        };
        den.pipes.beta = {
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
        den.pipes.items = {
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
        den.pipes.items = {
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
  };
}
