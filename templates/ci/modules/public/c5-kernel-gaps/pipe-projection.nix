# Guard tests for spawn-projected quirk surfacing (fix fd2c2a78).
#
# A deferred `spawn` policy (the host-aspects battery) projects a quirk-bearing
# host aspect onto a user's home. The aspect's static quirk emit is surfaced at
# the REQUESTING (user) scope so a pipe policy there behaves "as if the user
# included the aspect directly". These tests pin the surfacing's exactly-once
# semantics across every pipe reader (collect / expose / local), the genuine
# double-inclusion count, the multi-class union, and the host-bound boundary.
#
# host-emit interaction: because the projection projects the HOST's aspect tree,
# a host that carries the quirk-bearing aspect ALSO emits the quirk at its own
# (host) scope — separate from the user projection. The `({ user, ... }: true)`
# collects below select user scopes only (the entity-kind depth filter rejects
# host scopes), isolating the user-scope surfacing from the host emit.
{ denTest, lib, ... }:
let
  # "<count>|<sorted,dirs>" — count makes a duplicate surfacing observable
  # (a single ".claude/memory" surfaced twice reads "2|.claude/memory,.claude/memory").
  dirsStr =
    rh:
    "${toString (builtins.length rh)}|${
      lib.concatStringsSep "," (lib.sort (a: b: a < b) (builtins.concatMap (e: e.directories or [ ]) rh))
    }";
in
{
  flake.tests.pipe-projection = {

    # 1. A user-scope collectAll of the projected quirk sees it EXACTLY ONCE —
    # the spawn root is absent from the pre-drain scope universe, so there is no
    # spawn-root duplicate. The pull dual of the broadcast repro.
    test-collect-projected-quirk-once = denTest (
      {
        den,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.replicateHome.description = "home dirs to replicate";

        den.aspects.claude.replicateHome = [ { directories = [ ".claude/memory" ]; } ];
        den.aspects.iceberg.includes = [ den.aspects.claude ];
        den.aspects.alice.includes = [ den.batteries.host-aspects ];

        # USER scope: collect replicateHome from every OTHER user scope.
        den.policies.collect-rh =
          { user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "replicateHome" [ (pipe.collectAll ({ user, ... }: true)) ]) ];
        den.schema.user.includes = [ den.policies.collect-rh ];

        # tux: pure collector (no own projection) — sees alice's projected quirk once.
        den.aspects.tux.homeManager =
          { replicateHome, ... }:
          {
            home.sessionVariables.DIRS = dirsStr replicateHome;
          };

        expr = tuxHm.home.sessionVariables.DIRS;
        expected = "1|.claude/memory";
      }
    );

    # 2. Genuine double inclusion: iceberg HOST-includes claude (one host-scope
    # emit) AND alice PROJECTS it (one user-scope emit). The host emit is seen
    # once at the host; the user projection is collected once at a peer user —
    # the host emit does NOT leak into the user collect (kind filter) and the
    # surfacing is not doubled. Exactly twice in the system, one per inclusion.
    test-host-include-plus-projection-counted-once-each = denTest (
      {
        den,
        tuxHm,
        iceberg,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.replicateHome.description = "home dirs to replicate";

        den.aspects.claude.replicateHome = [ { directories = [ ".claude/memory" ]; } ];
        den.aspects.rh-host-consumer.nixos =
          { replicateHome, ... }:
          {
            networking.domain = dirsStr replicateHome;
          };
        # iceberg host-includes claude (host emit) AND a host consumer.
        den.aspects.iceberg.includes = [
          den.aspects.claude
          den.aspects.rh-host-consumer
        ];
        # alice projects claude onto her home (user emit).
        den.aspects.alice.includes = [ den.batteries.host-aspects ];

        den.policies.collect-rh =
          { user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "replicateHome" [ (pipe.collectAll ({ user, ... }: true)) ]) ];
        den.schema.user.includes = [ den.policies.collect-rh ];

        den.aspects.tux.homeManager =
          { replicateHome, ... }:
          {
            home.sessionVariables.DIRS = dirsStr replicateHome;
          };

        expr = {
          # tux collects alice's single user-scope projection — host emit excluded.
          userCollected = tuxHm.home.sessionVariables.DIRS;
          # iceberg's host scope carries the host inclusion once (no projection leak).
          hostSeen = iceberg.networking.domain;
        };
        expected = {
          userCollected = "1|.claude/memory";
          hostSeen = "1|.claude/memory";
        };
      }
    );

    # 3. pipe.expose of the projected quirk routes it UP to the parent (host)
    # scope. The host already emits its own copy (it includes claude), so it
    # reads own(1) + exposed(1) = 2. Without the surfacing alice has nothing to
    # expose and the host reads only its own (1).
    test-expose-projected-quirk-reaches-parent = denTest (
      {
        den,
        iceberg,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.replicateHome.description = "home dirs to replicate";

        den.aspects.claude.replicateHome = [ { directories = [ ".claude/memory" ]; } ];
        den.aspects.rh-host-consumer.nixos =
          { replicateHome, ... }:
          {
            networking.domain = dirsStr replicateHome;
          };
        den.aspects.iceberg.includes = [
          den.aspects.claude
          den.aspects.rh-host-consumer
        ];
        den.aspects.alice.includes = [ den.batteries.host-aspects ];

        # USER scope: expose replicateHome up to the parent (host) scope.
        den.policies.expose-rh =
          { user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "replicateHome" [ pipe.expose ]) ];
        den.schema.user.includes = [ den.policies.expose-rh ];

        expr = iceberg.networking.domain;
        expected = "2|.claude/memory,.claude/memory";
      }
    );

    # 4. A consumer AT the requesting (user) scope reads the projected quirk
    # locally — no collect/broadcast/expose — exercising the mkCombinedBase
    # reader over the surfaced emit. alice binds replicateHome locally (surfaced),
    # so she reads her own value, not the host's.
    test-local-consume-projected-quirk = denTest (
      {
        den,
        iceberg,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.replicateHome.description = "home dirs to replicate";

        # claude is emit-only here; alice carries the local consumer.
        den.aspects.claude.replicateHome = [ { directories = [ ".claude/memory" ]; } ];
        den.aspects.iceberg.includes = [ den.aspects.claude ];
        den.aspects.alice = {
          includes = [ den.batteries.host-aspects ];
          homeManager =
            { replicateHome, ... }:
            {
              home.sessionVariables.DIRS = dirsStr replicateHome;
            };
        };

        expr = iceberg.home-manager.users.alice.home.sessionVariables.DIRS;
        expected = "1|.claude/memory";
      }
    );

    # 5. Multi-class spawn: alice's classes drive the projection's spawn classes
    # (host-aspects spawns `user.classes`). With >1 class, each class's walk picks
    # up the (class-agnostic) quirk emit, but the surfacing must land it ONCE at
    # the user scope — not once per class. Observed via a peer collect so the
    # extra class's output is never forced.
    test-multi-class-spawn-surfaces-once = denTest (
      {
        den,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice.classes = [
          "homeManager"
          "extra"
        ];

        den.classes.extra.description = "second projected spawn class";
        den.quirks.replicateHome.description = "home dirs to replicate";

        den.aspects.claude.replicateHome = [ { directories = [ ".claude/memory" ]; } ];
        den.aspects.iceberg.includes = [ den.aspects.claude ];
        den.aspects.alice.includes = [ den.batteries.host-aspects ];

        den.policies.collect-rh =
          { user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "replicateHome" [ (pipe.collectAll ({ user, ... }: true)) ]) ];
        den.schema.user.includes = [ den.policies.collect-rh ];

        den.aspects.tux.homeManager =
          { replicateHome, ... }:
          {
            home.sessionVariables.DIRS = dirsStr replicateHome;
          };

        expr = tuxHm.home.sessionVariables.DIRS;
        expected = "1|.claude/memory";
      }
    );

    # 6. Host-bound boundary: when the projected quirk is ALSO bound by a
    # host-level pipe policy, the spawn strips it (strippableNames) and it is NOT
    # surfaced at the user scope — the user inherits the host's assembled value
    # instead. The host collects a DISTINCT extra entry ("host-extra"); alice
    # reading it proves inheritance, not the (suppressed) projected surfacing
    # (which would yield just ".claude/memory").
    test-host-bound-projected-quirk-not-surfaced = denTest (
      {
        den,
        iceberg,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        den.quirks.replicateHome.description = "home dirs to replicate";

        den.aspects.claude.replicateHome = [ { directories = [ ".claude/memory" ]; } ];
        den.aspects.host-extra.replicateHome = [ { directories = [ "host-extra" ]; } ];
        # host-level policy BINDS replicateHome at the host scope.
        den.policies.host-collect =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "replicateHome" [ (pipe.collectAll ({ host, ... }: true)) ]) ];
        den.aspects.iceberg.includes = [
          den.aspects.claude
          den.aspects.host-extra
          den.policies.host-collect
        ];
        # alice projects claude — but replicateHome is host-bound, so the spawn
        # strips it and it is not surfaced; alice inherits the host's value.
        den.aspects.alice = {
          includes = [ den.batteries.host-aspects ];
          homeManager =
            { replicateHome, ... }:
            {
              home.sessionVariables.DIRS = dirsStr replicateHome;
            };
        };

        expr = iceberg.home-manager.users.alice.home.sessionVariables.DIRS;
        expected = "2|.claude/memory,host-extra";
      }
    );

    # 7. Parametric per-user expansion: two users on one host each project the
    # SAME parametric quirk aspect. The emit must resolve at EACH user's scope
    # with THAT user (no collapse, no cross-bleed) — so a peer's collectAll sees
    # both users' DISTINCT values, one per projecting user.
    test-per-user-parametric-projection = denTest (
      {
        den,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };
        den.hosts.x86_64-linux.iceberg.users.bob = { };

        den.quirks.replicateHome.description = "home dirs to replicate";

        # Parametric: the dir is keyed by the projecting user.
        den.aspects.claude.replicateHome = { user, ... }: [ { directories = [ ".claude/${user.name}" ]; } ];
        den.aspects.iceberg.includes = [ den.aspects.claude ];
        den.aspects.alice.includes = [ den.batteries.host-aspects ];
        den.aspects.bob.includes = [ den.batteries.host-aspects ];

        den.policies.collect-rh =
          { user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "replicateHome" [ (pipe.collectAll ({ user, ... }: true)) ]) ];
        den.schema.user.includes = [ den.policies.collect-rh ];

        # tux collects every other user's projected emit: alice's + bob's, distinct.
        den.aspects.tux.homeManager =
          { replicateHome, ... }:
          {
            home.sessionVariables.DIRS = dirsStr replicateHome;
          };

        expr = tuxHm.home.sessionVariables.DIRS;
        expected = "2|.claude/alice,.claude/bob";
      }
    );
  };
}
