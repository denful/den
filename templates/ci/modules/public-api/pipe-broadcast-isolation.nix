# Defensive isolation coverage for pipe.broadcast — proving a broadcast does
# NOT leak across pipe names, entity kinds, predicate misses, or into collect.
{ denTest, lib, ... }:
{
  flake.tests.pipe-broadcast-isolation = {

    # Pipe-name isolation: a broadcast on `alpha` must not bleed into `beta`.
    # alice consumes BOTH pipes; only alpha carries tux's broadcast.
    test-broadcast-pipe-name-isolation = denTest (
      {
        den,
        iceberg,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.alpha.description = "pipe A";
        den.quirks.beta.description = "pipe B";

        den.aspects.tux.alpha = [ { who = "tux-alpha"; } ];
        den.aspects.alice.homeManager =
          {
            alpha,
            beta,
            ...
          }:
          {
            home.sessionVariables.ALPHA = lib.concatStringsSep "," (map (p: p.who) alpha);
            home.sessionVariables.BETA = lib.concatStringsSep "," (map (p: p.who) beta);
          };

        # Broadcast ONLY alpha to all users.
        den.policies.broadcast-alpha =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "alpha" [ (pipe.broadcast ({ user, ... }: true)) ]) ];
        den.schema.user.includes = [ den.policies.broadcast-alpha ];

        expr = {
          alpha = iceberg.home-manager.users.alice.home.sessionVariables.ALPHA;
          beta = iceberg.home-manager.users.alice.home.sessionVariables.BETA;
        };
        expected = {
          # alice receives tux's alpha broadcast.
          alpha = "tux-alpha";
          # beta is untouched — no cross-pipe leak.
          beta = "";
        };
      }
    );

    # Entity-kind isolation through shared context: a broadcast to HOST scopes
    # ({ host, ... }: true) must NOT leak to a home/user scope, even though user
    # scopes carry `host` in their context. The receiver's OWN entity kind
    # (user) is an extra kind not named by the predicate, so it is rejected.
    test-broadcast-host-target-excludes-home = denTest (
      {
        den,
        iceberg,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.peer-dev.description = "per-user device records";

        # tux emits + broadcasts to HOST scopes. alice emits nothing.
        den.aspects.tux.peer-dev = [ { who = "tux"; } ];
        den.aspects.alice.homeManager =
          { peer-dev, ... }:
          {
            home.sessionVariables.PEERS = lib.concatStringsSep "," (map (p: p.who) peer-dev);
          };

        # A pure-consumer HOST aspect on iceberg.
        den.aspects.iceberg.includes = [ den.aspects.host-consumer ];
        den.aspects.host-consumer.nixos =
          { peer-dev, ... }:
          {
            networking.domain = lib.concatStringsSep "," (map (p: p.who) peer-dev);
          };

        den.policies.broadcast-to-hosts =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "peer-dev" [ (pipe.broadcast ({ host, ... }: true)) ]) ];
        den.schema.user.includes = [ den.policies.broadcast-to-hosts ];

        expr = {
          # iceberg HOST scope is a valid receiver of the host-targeted broadcast.
          icebergHost = iceberg.networking.domain;
          # alice's HOME (a user scope) is NOT — host-targeted broadcast must not
          # reach it. alice binds locally (own broadcast effect) with empty base,
          # so this is a direct-reception check, not ancestor inheritance.
          aliceHome = iceberg.home-manager.users.alice.home.sessionVariables.PEERS;
        };
        expected = {
          icebergHost = "tux";
          aliceHome = "";
        };
      }
    );

    # No-match predicate: a broadcast whose predicate matches no scope makes no
    # distribution and does not error. Every user sees only its own base.
    test-broadcast-no-match-predicate = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.igloo.users.pingu = { };

        den.quirks.peer-dev.description = "per-user device records";

        den.aspects.tux = {
          peer-dev = [ { who = "tux"; } ];
          homeManager =
            { peer-dev, ... }:
            {
              home.sessionVariables.PEERS = lib.concatStringsSep "," (map (p: p.who) peer-dev);
            };
        };
        den.aspects.pingu = {
          peer-dev = [ { who = "pingu"; } ];
          homeManager =
            { peer-dev, ... }:
            {
              home.sessionVariables.PEERS = lib.concatStringsSep "," (map (p: p.who) peer-dev);
            };
        };

        # Predicate matches a non-existent user — nobody receives.
        den.policies.broadcast-ghost =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "peer-dev" [ (pipe.broadcast ({ user, ... }: user.name == "ghost")) ]) ];
        den.schema.user.includes = [ den.policies.broadcast-ghost ];

        expr = {
          tux = tuxHm.home.sessionVariables.PEERS;
          pingu = pinguHm.home.sessionVariables.PEERS;
        };
        expected = {
          tux = "tux";
          pingu = "pingu";
        };
      }
    );

    # Broadcast ↔ collect boundary: values pushed INTO a scope by a peer's
    # broadcast must NOT be re-collected by a collectAll on the same pipe.
    # collect reads raw (+ exposed) emits, never broadcast-injected data — so a
    # fleet collectAll counts each user's raw emit ONCE, not the broadcast-
    # amplified per-user view.
    test-broadcast-not-recollected = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.peer-dev.description = "per-user device records";

        # Both users emit AND broadcast to all users (so each user's assembled
        # view is amplified to 2 entries).
        den.aspects.tux.peer-dev = [ { who = "tux"; } ];
        den.aspects.alice.peer-dev = [ { who = "alice"; } ];

        den.policies.broadcast-peer-dev =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "peer-dev" [ (pipe.broadcast ({ user, ... }: true)) ]) ];
        den.schema.user.includes = [ den.policies.broadcast-peer-dev ];

        # A host-scope collectAll over USER scopes. Reads RAW emits only: tux + alice = 2.
        # If broadcast leaked into collect, each user scope would report 2 and the
        # total would be 4.
        den.policies.collect-peer-dev =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "peer-dev" [ (pipe.collectAll ({ user, ... }: true)) ]) ];
        den.schema.host.includes = [ den.policies.collect-peer-dev ];

        den.aspects.igloo.includes = [ den.aspects.counter ];
        den.aspects.counter.nixos =
          { peer-dev, ... }:
          {
            networking.domain = toString (builtins.length peer-dev);
          };

        expr = igloo.networking.domain;
        expected = "2";
      }
    );
  };
}
