# Tests for pipe.expose — upward scope flow from child to parent.
{ denTest, lib, ... }:
{
  flake.tests.pipe-scope = {

    # User pipe data exposed to host scope via pipe.expose.
    test-pipe-expose-basic = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.prefs = {
          description = "User preferences";
        };

        # User aspect produces pipe data.
        den.aspects.tux = {
          prefs = [
            { editor = "vim"; }
          ];
        };

        # Host aspect consumes pipe data (should see exposed user data).
        den.aspects.igloo = {
          includes = [ den.aspects.host-consumer ];
        };

        den.aspects.host-consumer = {
          nixos =
            { prefs, ... }:
            {
              networking.hostName = lib.concatMapStringsSep "-" (p: p.editor) prefs;
            };
        };

        den.policies.expose-prefs =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "prefs" [
              pipe.expose
            ])
          ];

        den.default.includes = [ den.policies.expose-prefs ];

        expr = igloo.networking.hostName;
        expected = "vim";
      }
    );

    # Transform stages applied before expose.
    test-pipe-expose-with-transform = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.items = {
          description = "Items";
        };

        den.aspects.tux = {
          items = [
            {
              name = "a";
              keep = true;
            }
            {
              name = "b";
              keep = false;
            }
          ];
        };

        den.aspects.igloo = {
          includes = [ den.aspects.item-consumer ];
        };

        den.aspects.item-consumer = {
          nixos =
            { items, ... }:
            {
              networking.hostName = lib.concatMapStringsSep "-" (i: i.label) items;
            };
        };

        den.policies.expose-filtered =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "items" [
              (pipe.filter (i: i.keep))
              (pipe.transform (i: {
                label = "x-${i.name}";
              }))
              pipe.expose
            ])
          ];

        den.default.includes = [ den.policies.expose-filtered ];

        # Only kept items, transformed, reach the host.
        expr = igloo.networking.hostName;
        expected = "x-a";
      }
    );

    # Exposed data merges with host-local pipe data.
    test-pipe-expose-with-local = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.ports = {
          description = "Port declarations";
        };

        # User aspect produces user-level ports.
        den.aspects.tux = {
          ports = [ 8080 ];
        };

        # Host aspect produces host-level ports AND consumes.
        den.aspects.igloo = {
          includes = [ den.aspects.port-consumer ];
          ports = [ 80 ];
        };

        den.aspects.port-consumer = {
          nixos =
            { ports, lib, ... }:
            {
              networking.firewall.allowedTCPPorts = lib.sort (a: b: a < b) ports;
            };
        };

        den.policies.expose-ports =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "ports" [
              pipe.expose
            ])
          ];

        den.default.includes = [ den.policies.expose-ports ];

        # Host consumer sees both host-local (80) and exposed user (8080).
        expr = igloo.networking.firewall.allowedTCPPorts;
        expected = [
          80
          8080
        ];
      }
    );

    # Exposed data from multiple users merges in host scope.
    test-pipe-expose-multi-user = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          users.pingu = { };
        };
        den.quirks.shells = {
          description = "Shell preferences";
        };

        den.aspects.tux = {
          shells = [ "zsh" ];
        };
        den.aspects.pingu = {
          shells = [ "fish" ];
        };

        den.aspects.igloo = {
          includes = [ den.aspects.shell-consumer ];
        };

        den.aspects.shell-consumer = {
          nixos =
            { shells, lib, ... }:
            {
              networking.hostName = lib.concatStringsSep "-" (lib.sort (a: b: a < b) shells);
            };
        };

        den.policies.expose-shells =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "shells" [
              pipe.expose
            ])
          ];

        den.default.includes = [ den.policies.expose-shells ];

        # Host sees shells from both users.
        expr = igloo.networking.hostName;
        expected = "fish-zsh";
      }
    );

    # Exposed data is NOT visible to sibling scopes — only parent.
    test-pipe-expose-sibling-isolation = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          users.pingu = { };
        };
        den.quirks.secrets = {
          description = "User secrets";
        };

        # tux exposes secrets
        den.aspects.tux = {
          secrets = [ { key = "tux-secret"; } ];
        };

        # pingu also has secrets and a consumer — should NOT see tux's exposed data
        den.aspects.pingu = {
          includes = [ den.aspects.pingu-consumer ];
          secrets = [ { key = "pingu-secret"; } ];
        };

        den.aspects.pingu-consumer = {
          nixos =
            { secrets, lib, ... }:
            {
              # pingu should only see its own local secret, not tux's exposed one
              networking.hostName = lib.concatMapStringsSep "-" (s: s.key) secrets;
            };
        };

        # Host consumer should see both (via expose)
        den.aspects.igloo = {
          includes = [ den.aspects.host-consumer ];
        };

        den.aspects.host-consumer = {
          nixos =
            { secrets, lib, ... }:
            {
              networking.domain = toString (builtins.length secrets);
            };
        };

        den.policies.expose-secrets =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "secrets" [
              pipe.expose
            ])
          ];

        den.default.includes = [ den.policies.expose-secrets ];

        expr = {
          # pingu sees only its own secret (sibling isolation)
          pinguHost = igloo.networking.hostName;
          # host sees both via expose
          hostCount = igloo.networking.domain;
        };
        expected = {
          pinguHost = "pingu-secret";
          hostCount = "2";
        };
      }
    );

    # Cross-host backend collection via pipe.collect.
    test-pipe-collect = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.http-backends = {
          description = "HTTP backends";
        };

        den.policies.fleet-backends =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "http-backends" [
              (pipe.collect ({ host, ... }: true))
            ])
          ];

        den.schema.host.includes = [ den.policies.fleet-backends ];

        den.aspects.iceberg = {
          http-backends = {
            addr = "10.0.0.2";
            port = 80;
          };
        };

        den.aspects.igloo = {
          includes = [ den.aspects.haproxy ];
          http-backends = {
            addr = "10.0.0.1";
            port = 80;
          };
        };

        den.aspects.haproxy = {
          nixos =
            { http-backends, ... }:
            {
              # igloo sees: local (10.0.0.1) + collected from iceberg (10.0.0.2) = 2
              networking.hostName = toString (builtins.length http-backends);
            };
        };

        expr = igloo.networking.hostName;
        expected = "2";
      }
    );

    # Collect + filter composition.
    test-pipe-collect-filter = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.http-backends = {
          description = "HTTP backends";
        };

        den.policies.fleet-backends =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "http-backends" [
              (pipe.collect ({ host, ... }: true))
              (pipe.filter (b: b.port != 8080))
            ])
          ];

        den.schema.host.includes = [ den.policies.fleet-backends ];

        den.aspects.iceberg = {
          http-backends = [
            {
              addr = "10.0.0.2";
              port = 80;
            }
            {
              addr = "10.0.0.2";
              port = 8080;
            }
          ];
        };

        den.aspects.igloo = {
          includes = [ den.aspects.haproxy ];
          http-backends = {
            addr = "10.0.0.1";
            port = 80;
          };
        };

        den.aspects.haproxy = {
          nixos =
            { http-backends, ... }:
            {
              # igloo: local (1) + collected from iceberg filtered (1, port 80 only) = 2
              networking.hostName = toString (builtins.length http-backends);
            };
        };

        expr = igloo.networking.hostName;
        expected = "2";
      }
    );

    # Self-exclusion: collect does not include current scope.
    test-pipe-collect-self-excluded = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.quirks.items = {
          description = "Items";
        };

        den.policies.collect-all =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "items" [
              (pipe.collect ({ host, ... }: true))
            ])
          ];

        den.schema.host.includes = [ den.policies.collect-all ];

        den.aspects.igloo = {
          includes = [ den.aspects.consumer ];
          items = {
            name = "local";
          };
        };

        den.aspects.consumer = {
          nixos =
            { items, ... }:
            {
              # Only local item, no peers to collect from. Self excluded.
              networking.hostName = toString (builtins.length items);
            };
        };

        expr = igloo.networking.hostName;
        expected = "1";
      }
    );
    # Fleet-based cross-host collection via user-defined fleet entity.
    # Fleet groups hosts under a shared parent scope so pipe.collect
    # sees all fleet members as siblings.
    test-pipe-collect-fleet = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.http-backends = {
          description = "HTTP backends";
        };

        # Fleet entity: groups all hosts under a fleet parent scope.
        den.policies.to-fleet = _: [
          (den.lib.policy.resolve.to "fleet" {
            fleet = {
              name = "fleet";
            };
          })
        ];

        den.policies.fleet-to-hosts =
          { fleet, ... }:
          lib.concatMap (
            system:
            lib.concatMap (
              hostName:
              let
                host = den.hosts.${system}.${hostName};
              in
              [
                (den.lib.policy.resolve.to "host" { inherit host; })
                (den.lib.policy.instantiate host)
              ]
            ) (builtins.attrNames (den.hosts.${system} or { }))
          ) (builtins.attrNames (den.hosts or { }));

        den.schema.flake.includes = [ den.policies.to-fleet ];
        den.schema.fleet.includes = [ den.policies.fleet-to-hosts ];

        # Collect policy: each host collects from fleet peers.
        den.policies.fleet-backends =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "http-backends" [
              (pipe.collect ({ host, ... }: true))
            ])
          ];

        den.schema.host.includes = [ den.policies.fleet-backends ];

        den.aspects.iceberg = {
          http-backends = {
            addr = "10.0.0.2";
            port = 80;
          };
        };

        den.aspects.igloo = {
          includes = [ den.aspects.haproxy ];
          http-backends = {
            addr = "10.0.0.1";
            port = 80;
          };
        };

        den.aspects.haproxy = {
          nixos =
            { http-backends, ... }:
            {
              # igloo sees: local (10.0.0.1) + collected from iceberg (10.0.0.2) = 2
              networking.hostName = toString (builtins.length http-backends);
            };
        };

        expr = igloo.networking.hostName;
        expected = "2";
      }
    );

    # Provenance wrapping: pipe.withProvenance annotates entries with source context.
    test-pipe-provenance = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.http-backends = {
          description = "HTTP backends";
        };

        den.policies.fleet-backends =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "http-backends" [
              (pipe.collect ({ host, ... }: true))
              pipe.withProvenance
            ])
          ];

        den.schema.host.includes = [ den.policies.fleet-backends ];

        den.aspects.iceberg = {
          http-backends = {
            addr = "10.0.0.2";
            port = 80;
          };
        };

        den.aspects.igloo = {
          includes = [ den.aspects.haproxy ];
          http-backends = {
            addr = "10.0.0.1";
            port = 80;
          };
        };

        den.aspects.haproxy = {
          nixos =
            { http-backends, ... }:
            {
              # With provenance, entries are { value, source }.
              # Local entry has source = igloo's context.
              # Collected entry has source = iceberg's context.
              networking.hostName = toString (builtins.length http-backends);
              networking.domain = lib.concatMapStringsSep "," (e: "${e.value.addr}:${e.source.host.name}") (
                lib.sort (a: b: a.value.addr < b.value.addr) http-backends
              );
            };
        };

        expr = {
          count = igloo.networking.hostName;
          detail = igloo.networking.domain;
        };
        expected = {
          count = "2";
          detail = "10.0.0.1:igloo,10.0.0.2:iceberg";
        };
      }
    );

    # Provenance + transform composition: transform runs on tagged values.
    test-pipe-provenance-with-transform = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.tags = {
          description = "Tags";
        };

        den.policies.collect-tags =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "tags" [
              (pipe.collect ({ host, ... }: true))
              (pipe.filter (t: t != "skip"))
              pipe.withProvenance
            ])
          ];

        den.schema.host.includes = [ den.policies.collect-tags ];

        den.aspects.iceberg = {
          tags = [
            "web"
            "skip"
          ];
        };

        den.aspects.igloo = {
          includes = [ den.aspects.tag-reader ];
          tags = [ "lb" ];
        };

        den.aspects.tag-reader = {
          nixos =
            { tags, ... }:
            {
              # "skip" filtered before provenance wrapping.
              # Remaining: local "lb" + collected "web" = 2 entries with provenance.
              networking.hostName = toString (builtins.length tags);
              networking.domain = lib.concatMapStringsSep "," (e: "${e.value}@${e.source.host.name}") (
                lib.sort (a: b: a.value < b.value) tags
              );
            };
        };

        expr = {
          count = igloo.networking.hostName;
          detail = igloo.networking.domain;
        };
        expected = {
          count = "2";
          detail = "lb@igloo,web@iceberg";
        };
      }
    );

    # Config-dependent thunk: pipe entry is a function that reads host config.
    test-pipe-config-thunk = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.ssh-keys = {
          description = "SSH host public keys";
        };

        den.policies.collect-keys =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "ssh-keys" [
              (pipe.collect ({ host, ... }: true))
            ])
          ];

        # Set hostname so config thunks can read it.
        den.aspects.set-hostname = {
          nixos =
            { host, ... }:
            {
              networking.hostName = host.name;
            };
        };
        den.schema.host.includes = [
          den.policies.collect-keys
          den.aspects.set-hostname
        ];

        # Config-dependent thunk: reads hostname from NixOS config.
        # The thunk is resolved lazily against instantiated configs.
        den.aspects.iceberg = {
          ssh-keys = { config, ... }: [ "key-${config.networking.hostName}" ];
        };

        den.aspects.igloo = {
          includes = [ den.aspects.key-consumer ];
          ssh-keys = { config, ... }: [ "key-${config.networking.hostName}" ];
        };

        den.aspects.key-consumer = {
          nixos =
            { ssh-keys, lib, ... }:
            {
              # igloo sees: local resolved thunk + collected from iceberg = 2 keys.
              networking.domain = lib.concatStringsSep "," (lib.sort (a: b: a < b) ssh-keys);
            };
        };

        expr = igloo.networking.domain;
        expected = "key-iceberg,key-igloo";
      }
    );

    # Config-dependent thunk with list-valued result (auto-flattened).
    test-pipe-config-thunk-list = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.quirks.ports = {
          description = "Port declarations";
        };

        den.aspects.set-hostname = {
          nixos =
            { host, ... }:
            {
              networking.hostName = host.name;
            };
        };
        den.default.includes = [ den.aspects.set-hostname ];

        # Thunk returns a list — should be auto-flattened.
        den.aspects.igloo = {
          includes = [ den.aspects.port-reader ];
          ports =
            { config, ... }:
            if config.networking.hostName == "igloo" then
              [
                80
                443
              ]
            else
              [ 8080 ];
        };

        den.aspects.port-reader = {
          nixos =
            { ports, lib, ... }:
            {
              networking.firewall.allowedTCPPorts = lib.sort (a: b: a < b) ports;
            };
        };

        expr = igloo.networking.firewall.allowedTCPPorts;
        expected = [
          80
          443
        ];
      }
    );

    # Mutual config dependency: two hosts read each other's non-overlapping config.
    test-pipe-config-thunk-mutual = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.peer-names = {
          description = "Peer host names";
        };

        den.policies.collect-peer-names =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "peer-names" [
              (pipe.collect ({ host, ... }: true))
            ])
          ];

        den.aspects.set-hostname = {
          nixos =
            { host, ... }:
            {
              networking.hostName = host.name;
            };
        };
        den.schema.host.includes = [
          den.policies.collect-peer-names
          den.aspects.set-hostname
        ];

        # Both hosts emit config-dependent thunks reading their own hostname.
        # Each host's hostname is set statically (not pipe-dependent), so
        # mutual lazy resolution works: igloo reads iceberg's config.networking.hostName
        # and vice versa without circular dep.
        den.aspects.iceberg = {
          peer-names = { config, ... }: config.networking.hostName;
        };

        den.aspects.igloo = {
          includes = [ den.aspects.name-consumer ];
          peer-names = { config, ... }: config.networking.hostName;
        };

        den.aspects.name-consumer = {
          nixos =
            { peer-names, lib, ... }:
            {
              # igloo sees: local "igloo" + collected "iceberg" = 2.
              networking.domain = lib.concatStringsSep "," (lib.sort (a: b: a < b) peer-names);
            };
        };

        expr = igloo.networking.domain;
        expected = "iceberg,igloo";
      }
    );

    # Config thunk that takes both pipeline args AND config in the thunk itself.
    # The pipe value function receives { host, config, ... } — host is a pipeline
    # entity binding, config is the NixOS fixpoint. Both resolve in the same thunk.
    test-pipe-config-thunk-both-paths = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.host-info = {
          description = "Host info combining entity name and config";
        };

        den.aspects.set-hostname = {
          nixos =
            { host, ... }:
            {
              networking.hostName = host.name;
            };
        };

        den.policies.collect-info =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "host-info" [
              (pipe.collect ({ host, ... }: true))
            ])
          ];

        den.schema.host.includes = [
          den.aspects.set-hostname
          den.policies.collect-info
        ];

        # The thunk itself takes { host, config, ... } — exercising both
        # pipeline arg (host.name) and NixOS config (networking.hostName)
        # in a single pipe value.
        den.aspects.iceberg = {
          host-info =
            { host, config, ... }:
            {
              ${host.name} = config.networking.hostName;
            };
        };

        den.aspects.igloo = {
          includes = [ den.aspects.info-reader ];
          host-info =
            { host, config, ... }:
            {
              ${host.name} = config.networking.hostName;
            };
        };

        den.aspects.info-reader = {
          nixos =
            { host-info, lib, ... }:
            {
              # Each entry is { <entity-name> = <config-hostname>; }.
              # Entity name comes from pipeline, config hostname from NixOS fixpoint.
              networking.domain =
                lib.concatMapStringsSep ","
                  (
                    entry:
                    let
                      k = builtins.head (builtins.attrNames entry);
                    in
                    "${k}=${entry.${k}}"
                  )
                  (
                    lib.sort (
                      a: b: builtins.head (builtins.attrNames a) < builtins.head (builtins.attrNames b)
                    ) host-info
                  );
            };
        };

        expr = igloo.networking.domain;
        expected = "iceberg=iceberg,igloo=igloo";
      }
    );

    # Entity kind filter: collect predicate { host, ... } rejects user scopes
    # even though user scopes also have `host` in context.
    test-pipe-collect-entity-kind-filter = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.host-tags = {
          description = "Host tags";
        };

        den.policies.collect-host-tags =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "host-tags" [
              (pipe.collect ({ host, ... }: true))
            ])
          ];

        den.schema.host.includes = [ den.policies.collect-host-tags ];

        # Both host and user aspects emit host-tags.
        # Only HOST scope entries should be collected — user scope entries
        # should be rejected by the entity kind filter.
        den.aspects.iceberg = {
          host-tags = [ "webserver" ];
        };

        den.aspects.alice = {
          host-tags = [ "user-tag-should-not-appear" ];
        };

        den.aspects.igloo = {
          includes = [ den.aspects.tag-consumer ];
          host-tags = [ "loadbalancer" ];
        };

        den.aspects.tag-consumer = {
          nixos =
            { host-tags, ... }:
            {
              # igloo sees: local "loadbalancer" + iceberg's "webserver" = 2
              # alice's "user-tag-should-not-appear" is rejected by entity kind filter.
              networking.hostName = toString (builtins.length host-tags);
            };
        };

        expr = igloo.networking.hostName;
        expected = "2";
      }
    );

    # CLAIM UNDER TEST (syncthing replicateHome §3): a USER-scope emit,
    # pipe.expose'd up to its host, then visible to a FLEET collectAll on a PEER
    # host — expose (user→host) THEN host rebroadcast THEN fleet collect.
    # TRUE  → igloo's host consumer sees its OWN exposed user (tux@igloo) AND
    #         iceberg's exposed user (alice@iceberg).
    # FALSE (adversarial-review claim) → igloo sees only tux@igloo.
    test-expose-then-fleet-collect = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.peer-dev = {
          description = "per-user device records";
        };

        # ONLY user aspects emit — isolates the user→host→fleet path (no host emit).
        den.aspects.tux = {
          peer-dev = [ { who = "tux@igloo"; } ];
        };
        den.aspects.alice = {
          peer-dev = [ { who = "alice@iceberg"; } ];
        };

        # user scope: expose each user's emit up to its host.
        den.policies.expose-peer-dev =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "peer-dev" [ pipe.expose ]) ];
        den.default.includes = [ den.policies.expose-peer-dev ];

        # host scope: fleet-collect peer-dev across all hosts.
        den.policies.collect-peer-dev =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "peer-dev" [ (pipe.collectAll ({ host, ... }: true)) ]) ];
        den.schema.host.includes = [ den.policies.collect-peer-dev ];

        den.aspects.igloo = {
          includes = [ den.aspects.peer-consumer ];
        };
        den.aspects.peer-consumer = {
          nixos =
            { peer-dev, lib, ... }:
            {
              networking.domain = lib.concatStringsSep "," (lib.sort (a: b: a < b) (map (p: p.who) peer-dev));
            };
        };

        expr = igloo.networking.domain;
        # rebroadcast WORKS → both; FAILS → "tux@igloo" only.
        expected = "alice@iceberg,tux@igloo";
      }
    );

    # ALTERNATIVE shape: a HOST-scope emit that maps over host.users, one record
    # per user (entity context only — no expose). If host emits are fleet-collectable
    # (they are: see test-pipe-collect / test-pipe-collect-fleet), each member sees
    # every host's every user.
    test-host-peruser-emit-fleet-collect = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.peer-dev = {
          description = "per-user device records, emitted at host scope";
        };

        # HOST-scope emit: iterate the host's own users, emit one record each.
        den.aspects.emit-peers = {
          peer-dev =
            { host, ... }:
            lib.mapAttrsToList (uname: _u: { who = "${uname}@${host.name}"; }) (host.users or { });
        };

        den.policies.collect-peer-dev =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "peer-dev" [ (pipe.collectAll ({ host, ... }: true)) ]) ];

        den.schema.host.includes = [
          den.aspects.emit-peers
          den.policies.collect-peer-dev
        ];

        den.aspects.igloo = {
          includes = [ den.aspects.peer-consumer ];
        };
        den.aspects.peer-consumer = {
          nixos =
            { peer-dev, lib, ... }:
            {
              networking.domain = lib.concatStringsSep "," (lib.sort (a: b: a < b) (map (p: p.who) peer-dev));
            };
        };

        expr = igloo.networking.domain;
        expected = "alice@iceberg,tux@igloo";
      }
    );
  };
}
