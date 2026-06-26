# Tests for pipe.broadcast — push primitive, dual of pipe.expose.
# A scope broadcasts a pipe's (post-transform) value to every OTHER scope
# matching a receiver predicate, fleet-wide. Receivers read the pipe normally.
{ denTest, lib, ... }:
{
  flake.tests.pipe-broadcast = {

    # Basic all-to-all: each user broadcasts peer-dev to every user scope
    # fleet-wide. tux's home sees its own base (tux) + alice's broadcast.
    test-broadcast-basic = denTest (
      {
        den,
        tuxHm,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.peer-dev.description = "per-user device records";

        den.aspects.tux = {
          peer-dev = [ { who = "tux@igloo"; } ];
          homeManager =
            { peer-dev, ... }:
            {
              home.sessionVariables.PEERS = lib.concatStringsSep "," (
                lib.sort (a: b: a < b) (map (p: p.who) peer-dev)
              );
            };
        };
        den.aspects.alice = {
          peer-dev = [ { who = "alice@iceberg"; } ];
        };

        # USER scope: broadcast peer-dev to all user scopes fleet-wide.
        den.policies.broadcast-peer-dev =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "peer-dev" [ (pipe.broadcast ({ user, ... }: true)) ]) ];
        den.schema.user.includes = [ den.policies.broadcast-peer-dev ];

        # tux's home sees BOTH its own and alice's broadcast peer-dev.
        expr = tuxHm.home.sessionVariables.PEERS;
        expected = "alice@iceberg,tux@igloo";
      }
    );

    # User → REMOTE host. alice (a user on iceberg) broadcasts her device
    # record to every HOST scope ({ host, ... }: true). igloo — a host on the
    # OTHER side of the fleet — consumes it at host scope. Crosses both the
    # entity-kind boundary (user → host) and the host boundary.
    test-broadcast-to-remote-host = denTest (
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

        den.aspects.alice = {
          peer-dev = [ { who = "alice@iceberg"; } ];
        };

        # USER scope: broadcast to all HOST scopes fleet-wide.
        den.policies.broadcast-to-hosts =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "peer-dev" [ (pipe.broadcast ({ host, ... }: true)) ]) ];
        den.schema.user.includes = [ den.policies.broadcast-to-hosts ];

        # igloo (remote relative to alice) consumes the broadcast at host scope.
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
        expected = "alice@iceberg";
      }
    );

    # Source-side transform stages apply BEFORE distribution: the broadcast
    # value is the transformed view, identical at every receiver.
    test-broadcast-source-transform = denTest (
      {
        den,
        tuxHm,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.peer-dev.description = "per-user device records";

        den.aspects.tux = {
          peer-dev = [ { who = "tux"; } ];
          homeManager =
            { peer-dev, ... }:
            {
              home.sessionVariables.PEERS = lib.concatStringsSep "," (
                lib.sort (a: b: a < b) (map (p: p.who) peer-dev)
              );
            };
        };
        den.aspects.alice = {
          peer-dev = [ { who = "alice"; } ];
        };

        # Transform (uppercase-style tag) runs source-side, then broadcast.
        den.policies.broadcast-peer-dev =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "peer-dev" [
              (pipe.transform (p: {
                who = "dev:${p.who}";
              }))
              (pipe.broadcast ({ user, ... }: true))
            ])
          ];
        den.schema.user.includes = [ den.policies.broadcast-peer-dev ];

        # tux's own value is transformed too (own untargeted path) + alice's
        # transformed broadcast → uniform "dev:" view everywhere.
        expr = tuxHm.home.sessionVariables.PEERS;
        expected = "dev:alice,dev:tux";
      }
    );

    # Predicate scoping (negative): a broadcast targeting USER scopes is NOT
    # visible to a HOST consumer — the receiver predicate gates by entity kind.
    test-broadcast-predicate-excludes-host = denTest (
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

        den.aspects.tux = {
          peer-dev = [ { who = "tux@igloo"; } ];
        };
        den.aspects.alice = {
          peer-dev = [ { who = "alice@iceberg"; } ];
        };

        # Broadcast to USER scopes only.
        den.policies.broadcast-peer-dev =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "peer-dev" [ (pipe.broadcast ({ user, ... }: true)) ]) ];
        den.schema.user.includes = [ den.policies.broadcast-peer-dev ];

        # HOST consumer reads peer-dev — should be empty (host is not a user).
        den.aspects.igloo = {
          includes = [ den.aspects.host-consumer ];
        };
        den.aspects.host-consumer = {
          nixos =
            { peer-dev, lib, ... }:
            {
              networking.domain = lib.concatStringsSep "," (map (p: p.who) peer-dev);
            };
        };

        expr = igloo.networking.domain;
        expected = "";
      }
    );

    # Self-exclusion (S≠R): a lone broadcaster sees only its own base, NOT a
    # duplicate of its own broadcast value.
    test-broadcast-self-excluded = denTest (
      {
        den,
        tuxHm,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.quirks.peer-dev.description = "per-user device records";

        den.aspects.tux = {
          peer-dev = [ { who = "tux@igloo"; } ];
          homeManager =
            { peer-dev, ... }:
            {
              home.sessionVariables.PEERS = lib.concatStringsSep "," (map (p: p.who) peer-dev);
            };
        };

        den.policies.broadcast-peer-dev =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "peer-dev" [ (pipe.broadcast ({ user, ... }: true)) ]) ];
        den.schema.user.includes = [ den.policies.broadcast-peer-dev ];

        # Only tux's own base — no self-broadcast duplicate.
        expr = tuxHm.home.sessionVariables.PEERS;
        expected = "tux@igloo";
      }
    );

    # No leak: a narrow predicate reaches ONLY matching scopes. Every user
    # broadcasts to tux alone ({ user }: user.name == "tux"). tux receives
    # pingu's record; pingu receives NOTHING (tux's broadcast must not leak to
    # a non-matching peer). Both homes inspected.
    test-broadcast-targeted-no-leak = denTest (
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
              home.sessionVariables.PEERS = lib.concatStringsSep "," (
                lib.sort (a: b: a < b) (map (p: p.who) peer-dev)
              );
            };
        };
        den.aspects.pingu = {
          peer-dev = [ { who = "pingu"; } ];
          homeManager =
            { peer-dev, ... }:
            {
              home.sessionVariables.PEERS = lib.concatStringsSep "," (
                lib.sort (a: b: a < b) (map (p: p.who) peer-dev)
              );
            };
        };

        den.policies.broadcast-to-tux =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "peer-dev" [ (pipe.broadcast ({ user, ... }: user.name == "tux")) ]) ];
        den.schema.user.includes = [ den.policies.broadcast-to-tux ];

        expr = {
          tux = tuxHm.home.sessionVariables.PEERS;
          pingu = pinguHm.home.sessionVariables.PEERS;
        };
        expected = {
          # tux receives pingu's broadcast + own base.
          tux = "pingu,tux";
          # pingu is not a target — sees only its own base. No leak.
          pingu = "pingu";
        };
      }
    );

    # Compound { host, user } targeting: a predicate requiring BOTH host and
    # user selects USER scopes (host scopes lack `user`) and can filter on the
    # receiver's host. alice@iceberg broadcasts to user scopes on igloo only.
    # tux@igloo receives; alice@iceberg (wrong host) does not.
    test-broadcast-target-host-user = denTest (
      {
        den,
        iceberg,
        tuxHm,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.peer-dev.description = "per-user device records";

        den.aspects.tux = {
          peer-dev = [ { who = "tux@igloo"; } ];
          homeManager =
            { peer-dev, ... }:
            {
              home.sessionVariables.PEERS = lib.concatStringsSep "," (
                lib.sort (a: b: a < b) (map (p: p.who) peer-dev)
              );
            };
        };
        den.aspects.alice = {
          peer-dev = [ { who = "alice@iceberg"; } ];
          homeManager =
            { peer-dev, ... }:
            {
              home.sessionVariables.PEERS = lib.concatStringsSep "," (
                lib.sort (a: b: a < b) (map (p: p.who) peer-dev)
              );
            };
        };

        # Target user scopes whose host is igloo (requires host AND user in ctx).
        den.policies.broadcast-to-igloo-users =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "peer-dev" [ (pipe.broadcast ({ host, user, ... }: host.name == "igloo")) ]) ];
        den.schema.user.includes = [ den.policies.broadcast-to-igloo-users ];

        expr = {
          tux = tuxHm.home.sessionVariables.PEERS;
          alice = iceberg.home-manager.users.alice.home.sessionVariables.PEERS;
        };
        expected = {
          # tux (user on igloo) receives alice's broadcast + own base.
          tux = "alice@iceberg,tux@igloo";
          # alice (user on iceberg) is not targeted — own base only.
          alice = "alice@iceberg";
        };
      }
    );
  };
}
