{ denTest, ... }:
{
  flake.tests.home-extraction = {
    # A pipeline-parametric pipe collected across a fleet must resolve to
    # concrete DATA at the consumer even when no host configs are available on
    # the collected path. Before the fix, the raw `{ host, ... }: ...` lambda
    # crossed the collected path unresolved when hostConfigs == null, crashing
    # the consumer with "expected a set but found a function".
    test-collected-parametric-no-config-resolves = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      let
        inherit (den.lib.policy) pipe resolve instantiate;
      in
      {
        den.quirks.host-addrs.description = "Host address entries";
        den.policies.to-fleet = _: [
          (resolve.to "fleet" {
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
                (resolve.to "host" { inherit host; })
                (instantiate host)
              ]
            ) (builtins.attrNames (den.hosts.${system} or { }))
          ) (builtins.attrNames (den.hosts or { }));
        den.policies.collect-addrs = _: [
          (pipe.from "host-addrs" [ (pipe.collectAll ({ host, ... }: true)) ])
        ];
        den.schema.flake.includes = [ den.policies.to-fleet ];
        den.schema.fleet.includes = [ den.policies.fleet-to-hosts ];
        den.schema.host.includes = [ den.policies.collect-addrs ];
        den.schema.flake-system.excludes = [
          den.policies.system-to-os-outputs
          den.policies.system-to-hm-outputs
        ];

        den.hosts.x86_64-linux.igloo.users = { };
        den.hosts.x86_64-linux.iceberg.users = { };
        den.aspects.igloo.host-addrs =
          { host, ... }:
          {
            hostname = host.name;
          };
        den.aspects.iceberg.host-addrs =
          { host, ... }:
          {
            hostname = host.name;
          };
        den.aspects.igloo.nixos =
          {
            host-addrs,
            lib,
            ...
          }:
          {
            networking.extraHosts = lib.concatStringsSep "," (
              lib.sort (a: b: a < b) (map (e: e.hostname) host-addrs)
            );
          };

        expr = igloo.networking.extraHosts;
        expected = "iceberg,igloo";
      }
    );

    # A pipeline-parametric pipe exposed upward (child → parent) must resolve to
    # concrete DATA at the exposing scope (the user node) before crossing the
    # P edge to the host consumer. Before the fix, the raw `{ user, ... }: ...`
    # lambda crossed the expose path unresolved, crashing the host consumer with
    # "expected a set but found a function".
    test-exposed-parametric-resolves = denTest (
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
        den.quirks.resolved-users.description = "Users resolved onto a host";
        den.policies.expose-users = { user, ... }: [ (pipe.from "resolved-users" [ pipe.expose ]) ];
        den.schema.user.includes = [ den.policies.expose-users ];
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.aspects.tux.resolved-users =
          { user, ... }:
          {
            name = user.userName;
          };
        den.aspects.pingu.resolved-users =
          { user, ... }:
          {
            name = user.userName;
          };
        den.aspects.igloo.nixos =
          { resolved-users, lib, ... }:
          {
            users.groups.wheel.members = lib.sort (a: b: a < b) (map (u: u.name) resolved-users);
          };
        expr = igloo.users.groups.wheel.members;
        expected = [
          "pingu"
          "tux"
        ];
      }
    );

    # A config-dependent pipe entry exposed upward must STAY deferred: the
    # __configThunk marker (now also stamped at the emitting child node, in
    # addition to the consuming host's mkCombinedBase) must survive the expose
    # crossing and be resolved in the host's evalModules fixpoint. The user emits
    # a thunk reading the host's NixOS config; the host consumer reads the resolved value.
    test-exposed-config-thunk-defers = denTest (
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
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.quirks.host-marks.description = "Host-config-derived marks from users";

        # Host sets its hostname statically (not pipe-dependent), so the
        # config-dependent thunk can read it without a circular dependency.
        den.aspects.set-hostname = {
          nixos =
            { host, ... }:
            {
              networking.hostName = host.name;
            };
        };

        den.policies.expose-marks = { user, ... }: [ (pipe.from "host-marks" [ pipe.expose ]) ];
        den.schema.user.includes = [ den.policies.expose-marks ];
        den.schema.host.includes = [ den.aspects.set-hostname ];

        # Config-dependent emit at the user node: must defer (marked
        # __configThunk). Under producer-class resolution the user's `config` is
        # its home-manager config, so a HOST-derived mark reads the enclosing
        # host via `osConfig` (home-manager convention).
        den.aspects.tux.host-marks = { osConfig, ... }: [ "mark-${osConfig.networking.hostName}" ];

        den.aspects.igloo.nixos =
          { host-marks, lib, ... }:
          {
            networking.domain = lib.concatStringsSep "," (lib.sort (a: b: a < b) host-marks);
          };

        expr = igloo.networking.domain;
        expected = "mark-igloo";
      }
    );

    # host-aspects-projected homeManager consumer of a fleet-collected pipe must
    # see ALL fleet peers, not just its own host. The projection is materialized
    # via a deferred policy.spawn marker resolved post-walk over the parent's
    # full scope-tree state (host + siblings), so collectAll finds every host.
    test-host-aspects-all-peers = denTest (
      {
        den,
        tuxHm,
        lib,
        ...
      }:
      let
        inherit (den.lib.policy) pipe resolve instantiate;
      in
      {
        den.quirks.host-addrs.description = "Host address entries";
        den.policies.to-fleet = _: [
          (resolve.to "fleet" {
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
                (resolve.to "host" { inherit host; })
                (instantiate host)
              ]
            ) (builtins.attrNames (den.hosts.${system} or { }))
          ) (builtins.attrNames (den.hosts or { }));
        den.policies.collect-addrs = _: [
          (pipe.from "host-addrs" [ (pipe.collectAll ({ host, ... }: true)) ])
        ];
        den.schema.flake.includes = [ den.policies.to-fleet ];
        den.schema.fleet.includes = [ den.policies.fleet-to-hosts ];
        den.schema.host.includes = [ den.policies.collect-addrs ];
        den.schema.flake-system.excludes = [
          den.policies.system-to-os-outputs
          den.policies.system-to-hm-outputs
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };
        den.aspects.igloo.host-addrs =
          { host, ... }:
          {
            hostname = host.name;
          };
        den.aspects.iceberg.host-addrs =
          { host, ... }:
          {
            hostname = host.name;
          };
        # Host aspect projects an HM consumer of the fleet-collected pipe onto users.
        den.aspects.igloo.homeManager =
          { host-addrs, lib, ... }:
          {
            home.sessionVariables.HOSTS = lib.concatStringsSep "," (
              lib.sort (a: b: a < b) (map (e: e.hostname) host-addrs)
            );
          };
        den.aspects.tux.includes = [ den.batteries.host-aspects ];
        expr = tuxHm.home.sessionVariables.HOSTS;
        expected = "iceberg,igloo";
      }
    );

    # The user's OWN homeManager (makeHomeEnv forward source, NOT the
    # host-aspects battery) consuming a fleet-collected pipe must also see ALL
    # peers. Its forward SOURCE resolves via spawnNode threaded with the
    # parent scope-tree state (host + siblings), so collectAll finds every host
    # — exactly as the host-aspects projection does.
    test-user-own-all-peers = denTest (
      {
        den,
        tuxHm,
        lib,
        ...
      }:
      let
        inherit (den.lib.policy) pipe resolve instantiate;
      in
      {
        den.quirks.host-addrs.description = "Host address entries";
        den.policies.to-fleet = _: [
          (resolve.to "fleet" {
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
                (resolve.to "host" { inherit host; })
                (instantiate host)
              ]
            ) (builtins.attrNames (den.hosts.${system} or { }))
          ) (builtins.attrNames (den.hosts or { }));
        den.policies.collect-addrs = _: [
          (pipe.from "host-addrs" [ (pipe.collectAll ({ host, ... }: true)) ])
        ];
        den.schema.flake.includes = [ den.policies.to-fleet ];
        den.schema.fleet.includes = [ den.policies.fleet-to-hosts ];
        den.schema.host.includes = [ den.policies.collect-addrs ];
        den.schema.flake-system.excludes = [
          den.policies.system-to-os-outputs
          den.policies.system-to-hm-outputs
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };
        den.aspects.igloo.host-addrs =
          { host, ... }:
          {
            hostname = host.name;
          };
        den.aspects.iceberg.host-addrs =
          { host, ... }:
          {
            hostname = host.name;
          };
        # The user's OWN homeManager consumes the host-collected pipe
        # (no host-aspects battery).
        den.aspects.tux.homeManager =
          { host-addrs, lib, ... }:
          {
            home.sessionVariables.HOSTS = lib.concatStringsSep "," (
              lib.sort (a: b: a < b) (map (e: e.hostname) host-addrs)
            );
          };
        expr = tuxHm.home.sessionVariables.HOSTS;
        expected = "iceberg,igloo";
      }
    );

    # A COMPLEX forward (carries an adapterModule, so it is not a Tier-1 simple
    # route and its source is NOT pre-collected) into homeManager, living in a
    # host aspect projected onto the user via host-aspects. Because the source
    # is uncollected, the route fold takes the resolveSourceFallback path inside
    # the spawned home node — exercising spawn-node.nix's `applyRoutes selfRef`
    # with the { from, class, aspect, bindings } resolver contract. The source
    # aspect consumes the fleet-collected host-addrs pipe, so the result guards
    # BOTH: (a) selfRef must be the spawnNode primitive (an isolated
    # fxResolveImports would crash on the new signature), and (b) the fallback's
    # `from = scopeParent.<userScope>` host-scope lookup (a degenerate
    # `from = sourceScopeId` self-parent edge yields zero fleet peers / trips
    # spawnNode's spawnRoot==from assert).
    test-complex-forward-source-fallback-all-peers = denTest (
      {
        den,
        tuxHm,
        lib,
        ...
      }:
      let
        inherit (den.lib.policy) pipe resolve instantiate;
      in
      {
        den.quirks.host-addrs.description = "Host address entries";
        den.policies.to-fleet = _: [
          (resolve.to "fleet" {
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
                (resolve.to "host" { inherit host; })
                (instantiate host)
              ]
            ) (builtins.attrNames (den.hosts.${system} or { }))
          ) (builtins.attrNames (den.hosts or { }));
        den.policies.collect-addrs = _: [
          (pipe.from "host-addrs" [ (pipe.collectAll ({ host, ... }: true)) ])
        ];
        den.schema.flake.includes = [ den.policies.to-fleet ];
        den.schema.fleet.includes = [ den.policies.fleet-to-hosts ];
        den.schema.host.includes = [ den.policies.collect-addrs ];
        den.schema.flake-system.excludes = [
          den.policies.system-to-os-outputs
          den.policies.system-to-hm-outputs
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };
        den.aspects.igloo.host-addrs =
          { host, ... }:
          {
            hostname = host.name;
          };
        den.aspects.iceberg.host-addrs =
          { host, ... }:
          {
            hostname = host.name;
          };

        # A complex forward (adapterModule -> needsAdapter -> NOT a Tier-1 route,
        # source uncollected) from a forward-only class into homeManager. The
        # forward source is the user entity (mirrors makeHomeEnv's userForward),
        # so spawnNode re-establishes the user scope (spawnRoot != from) and
        # the source class key consumes the fleet-collected host-addrs pipe. The
        # forward lives in the host aspect tree, projected onto the user via
        # host-aspects, so its source is resolved inside the spawned home node.
        den.aspects.igloo.includes = [
          (den.batteries.forward {
            each = [ true ];
            fromClass = _: "hm-addrs-src";
            intoClass = _: "homeManager";
            intoPath = _: [
              "home"
              "sessionVariables"
            ];
            adapterModule = _: { };
            fromAspect =
              _:
              den.lib.resolveEntity "user" {
                host = den.hosts.x86_64-linux.igloo;
                user = den.hosts.x86_64-linux.igloo.users.tux;
              };
          })
        ];

        # The user's own aspect supplies the forward source class key, consuming
        # the fleet-collected pipe.
        den.aspects.tux.hm-addrs-src =
          { host-addrs, lib, ... }:
          {
            HOSTS = lib.concatStringsSep "," (lib.sort (a: b: a < b) (map (e: e.hostname) host-addrs));
          };

        den.aspects.tux.includes = [ den.batteries.host-aspects ];
        expr = tuxHm.home.sessionVariables.HOSTS;
        expected = "iceberg,igloo";
      }
    );

    # Equivalency invariant: in-tree resolution ≡ threaded (spawned-node)
    # resolution. A single fleet-collected pipe (host-addrs) is consumed BOTH by
    # a host-scope nixos consumer (resolved in-tree, on the main walk) AND by a
    # host-aspects-projected homeManager consumer (resolved in a spawned home
    # node threaded with the parent scope-tree state). Both must derive the
    # IDENTICAL fleet-wide value — any divergence between the two resolution
    # paths fails the test. This is the decisive guard that spawnNode is
    # behaviour-preserving: the threaded node sees exactly what the in-tree
    # consumer sees. Both consumers apply the SAME reduction over host-addrs, so
    # equality isolates the resolved pipe data as the only variable (don't
    # simplify one consumer's reduction — that would silently weaken the guard).
    test-equivalency-intree-eq-threaded = denTest (
      {
        den,
        igloo,
        tuxHm,
        lib,
        ...
      }:
      let
        inherit (den.lib.policy) pipe resolve instantiate;
      in
      {
        den.quirks.host-addrs.description = "Host address entries";
        den.policies.to-fleet = _: [
          (resolve.to "fleet" {
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
                (resolve.to "host" { inherit host; })
                (instantiate host)
              ]
            ) (builtins.attrNames (den.hosts.${system} or { }))
          ) (builtins.attrNames (den.hosts or { }));
        den.policies.collect-addrs = _: [
          (pipe.from "host-addrs" [ (pipe.collectAll ({ host, ... }: true)) ])
        ];
        den.schema.flake.includes = [ den.policies.to-fleet ];
        den.schema.fleet.includes = [ den.policies.fleet-to-hosts ];
        den.schema.host.includes = [ den.policies.collect-addrs ];
        den.schema.flake-system.excludes = [
          den.policies.system-to-os-outputs
          den.policies.system-to-hm-outputs
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };
        den.aspects.igloo.host-addrs =
          { host, ... }:
          {
            hostname = host.name;
          };
        den.aspects.iceberg.host-addrs =
          { host, ... }:
          {
            hostname = host.name;
          };

        # In-tree consumer: host-scope nixos, resolved on the main walk.
        den.aspects.igloo.nixos =
          { host-addrs, lib, ... }:
          {
            networking.extraHosts = lib.concatStringsSep "," (
              lib.sort (a: b: a < b) (map (e: e.hostname) host-addrs)
            );
          };
        # Threaded consumer: homeManager projected onto tux via host-aspects,
        # resolved in a spawned home node. Same-shaped derivation of the same
        # fleet-collected pipe.
        den.aspects.igloo.homeManager =
          { host-addrs, lib, ... }:
          {
            home.sessionVariables.HOSTS = lib.concatStringsSep "," (
              lib.sort (a: b: a < b) (map (e: e.hostname) host-addrs)
            );
          };
        den.aspects.tux.includes = [ den.batteries.host-aspects ];

        expr = {
          inTree = igloo.networking.extraHosts;
          threaded = tuxHm.home.sessionVariables.HOSTS;
        };
        expected = {
          inTree = "iceberg,igloo";
          threaded = "iceberg,igloo";
        };
      }
    );

    # Server-host membership (per-host-resolved boundary). Two hosts, each with a
    # distinct NON-admin user, each user exposing `resolved-users` upward. The
    # host aggregates ONLY the users resolved onto THAT host — collectAllExposed
    # walks each parent's own children, so host A's aggregation contains exactly
    # host A's users and NEVER host B's. This surfaces the boundary an admin-less
    # server relies on: a consumer like initrd-SSH reading `resolved-users` here
    # sees only this host's (non-admin) members, not a global registry. The test
    # asserts the TRUE current per-host behaviour — it does not change which users
    # resolve onto a host (a separate nix-config concern).
    test-server-host-membership-per-host = denTest (
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
        den.quirks.resolved-users.description = "Users resolved onto a host";
        den.policies.expose-users = { user, ... }: [ (pipe.from "resolved-users" [ pipe.expose ]) ];
        den.schema.user.includes = [ den.policies.expose-users ];

        # Two separate hosts, each with its own distinct non-admin user. Neither
        # user is in wheel/admin — this models an admin-less server.
        den.hosts.x86_64-linux.igloo.users.svc-igloo = { };
        den.hosts.x86_64-linux.iceberg.users.svc-iceberg = { };

        den.aspects.svc-igloo.resolved-users =
          { user, ... }:
          {
            name = user.userName;
          };
        den.aspects.svc-iceberg.resolved-users =
          { user, ... }:
          {
            name = user.userName;
          };

        # The host consumer enumerates resolved-users. The assertion makes the
        # per-host boundary visible: igloo sees only svc-igloo, NOT svc-iceberg.
        den.aspects.igloo.nixos =
          { resolved-users, lib, ... }:
          {
            users.groups.svc.members = lib.sort (a: b: a < b) (map (u: u.name) resolved-users);
          };

        expr = igloo.users.groups.svc.members;
        # Exactly this host's resolved users — iceberg's user must NOT appear.
        expected = [ "svc-igloo" ];
      }
    );
  };
}
