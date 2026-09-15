# delivery-edges suite — snapshot fixtures + rule-corollary tests for the
# PRODUCTION delivery-edge object (resolveWithPaths .edgeTrace, Task 18.2). As of
# Task 18.2 `edgeTrace` is the production edge object: its fold-ordered
# provides+routes portion is CAPTURED from the production materializeUnified folds
# (not re-derived), with constructor-built default-fold + instantiate edges and the
# SURFACED spawn / per-host edges. This means (vs the legacy re-derivation, whose
# `legacyEdgeTrace` binding has since been retired): the dedup-suppressed route
# twins are ABSENT (production never
# dispatches them), the spawn rewalk arm is replaced by the spawn's real surfaced
# edges, and instantiate topologies carry the per-host fold edges.
#
# Each fixture resolves a minimal topology and asserts its normalized delivery
# edge list. Scope id_hashes are normalized to "<kind>:<entityName>" so the
# expected lists stay readable and stable (the raw trace uses parent-blind
# id_hash identity, spec §8). Where a topology's full list is large but the
# mechanism under test is a small subset, the test asserts the exact subset for
# that mechanism plus the total edge count (noted inline).
#
# `just ci delivery-edges` runs this suite; `just ci delivery-edges.<test>` one
# test with traces.
{ denTest, lib, ... }:
let
  # Replace "<kind>:<id_hash>" scope strings in an edge trace with
  # "<kind>:<entityName>". id_hash → name is recovered from the resolve result's
  # scopeContexts (each entity scope's own record carries name + id_hash).
  normalizeTrace =
    r:
    let
      sc = r.scopeContexts or { };
      hashToName = lib.foldl' (
        acc: sid:
        let
          ctx = sc.${sid} or { };
          # Map EVERY entity record present in this scope's ctx (a child scope
          # carries its own + ancestor records, e.g. a user scope has both `user`
          # and `host`), so id_hash → name is built for all kinds, not just the
          # scope's own.
          entityKeys = lib.filter (k: builtins.isAttrs (ctx.${k} or null) && (ctx.${k} ? id_hash)) (
            builtins.attrNames ctx
          );
        in
        acc
        // lib.listToAttrs (
          map (k: lib.nameValuePair "${k}:${ctx.${k}.id_hash}" "${k}:${ctx.${k}.name or "?"}") entityKeys
        )
      ) { } (builtins.attrNames sc);
      ren = s: hashToName.${s} or s;
      # rewalk aspect ids are BARE id_hashes (no "<kind>:" prefix), so build a
      # bare-hash → "<kind>:<name>" map alongside the prefixed one above.
      bareHashToName = lib.mapAttrs' (
        k: v: lib.nameValuePair (lib.last (lib.splitString ":" k)) v
      ) hashToName;
      renAspect = s: bareHashToName.${s} or (hashToName.${s} or s);
      renSource =
        src:
        if src ? collected then
          {
            collected = src.collected // {
              scope = ren src.collected.scope;
            };
          }
        else if src ? rewalk then
          {
            rewalk = src.rewalk // {
              aspect = renAspect src.rewalk.aspect;
            };
          }
        else
          src;
      renTarget = t: if t ? root then t // { root = ren t.root; } else t;
      # Rename scope names inside the collectedScopes / spawnFrom annotations so
      # default-fold and spawn edges stay readable in expected lists.
      renAnnotations =
        a:
        a
        // lib.optionalAttrs (a ? collectedScopes) {
          collectedScopes = map ren a.collectedScopes;
        }
        // lib.optionalAttrs (a ? spawnFrom && a.spawnFrom != null) {
          spawnFrom = ren a.spawnFrom;
        };
    in
    map (
      e:
      e
      // {
        source = renSource e.source;
        target = renTarget e.target;
        annotations = renAnnotations e.annotations;
      }
    ) r.edgeTrace;

  # Resolve a host entity to a normalized edge trace.
  hostTrace =
    den: cls: host:
    normalizeTrace (
      den.lib.aspects.resolveWithPaths cls (den.lib.resolveEntity "host" { inherit host; })
    );

  # Resolve the flake root to a normalized edge trace.
  flakeTrace =
    den: cls: normalizeTrace (den.lib.aspects.resolveWithPaths cls (den.lib.resolveEntity "flake" { }));

  # Edge constructors mirroring edge-trace.nix's record shape (for readable
  # expected lists).
  collected = scope: class: { collected = { inherit scope class; }; };
  rewalk = aspect: bindings: class: { rewalk = { inherit aspect bindings class; }; };
  synthesize = forwardId: fromClass: intoClass: {
    synthesize = { inherit forwardId fromClass intoClass; };
  };
  rootT = root: class: { inherit root class; };
  outT = output: { inherit output; };
  edge =
    {
      source,
      target,
      path ? [ ],
      mode,
      annotations ? { },
    }:
    {
      inherit
        source
        target
        path
        mode
        annotations
        ;
    };

  # The host-default-user homeManager→nixos forward (every host with a user gets
  # one) plus the user-class ensureEntry route — shared tail of the host+user
  # fixtures. Parameterized by the host/user names and the os class (nixos |
  # darwin). The production edge object (Task 18.2) CAPTURES the edges its fold
  # dispatched (kept routes only), so the legacy oracle's dedup-suppressed twin is
  # NOT present here — production never dispatches it.
  userForwardTail =
    {
      user,
      os,
    }:
    [
      (edge {
        source = synthesize "homeManager/${os}/home-manager/users/${user}" "homeManager" os;
        target = rootT "user:${user}" os;
        path = [
          "home-manager"
          "users"
          user
        ];
        mode = "nest";
        annotations = {
          complexForward = true;
          sourceVia = "unresolved";
        };
      })
      (edge {
        source = collected "user:${user}" "user";
        target = rootT "user:${user}" os;
        path = [
          "users"
          "users"
          user
        ];
        mode = "nest";
        annotations = {
          adaptArgs = true;
          ensureTargetPath = true;
        };
      })
    ];
in
{
  flake.tests.delivery-edges = {

    # ===== (1) host + single user =====================================
    # Full edge list. Default folds (host homeManager/nixos, host+user os→nixos),
    # the user-forward tail (complex forward + dedup-suppressed twin + user
    # ensureEntry route). os→nixos is the os-class delivery route.
    test-topology-host-users = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = hostTrace den "nixos" den.hosts.x86_64-linux.igloo;
        expected = [
          (edge {
            source = collected "host:igloo" "homeManager";
            target = rootT "host:igloo" "homeManager";
            mode = "merge";
            annotations = {
              collectedScopes = [
                "host:igloo"
                "user:tux"
              ];
            };
          })
          (edge {
            source = collected "host:igloo" "nixos";
            target = rootT "host:igloo" "nixos";
            mode = "merge";
            annotations = {
              collectedScopes = [
                "host:igloo"
                "user:tux"
              ];
            };
          })
          (edge {
            source = collected "host:igloo" "os";
            target = rootT "host:igloo" "nixos";
            mode = "merge";
          })
          (edge {
            source = collected "user:tux" "os";
            target = rootT "user:tux" "nixos";
            mode = "merge";
          })
        ]
        ++ userForwardTail {
          user = "tux";
          os = "nixos";
        };
      }
    );

    # ===== (2) fleet with environment ancestor ========================
    # Flake-level resolve through a fleet ancestor. The instantiate edge is
    # SOURCED from the fleet ancestor scope (resolve.to "host" registered the
    # instantiate at the fleet scope). The production object (Task 18.2) also
    # carries the per-host surfaced fold edges (host:igloo HM/nixos folds + the
    # os→nixos delivery route) the instantiate projection adds. The os→nixos route
    # appears twice (the per-host + B′ projections both surface it; the union does
    # not dedup). Full list.
    test-topology-fleet-environment = denTest (
      { den, lib, ... }:
      {
        den.quirks.host-addrs.description = "addrs";
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
        den.schema.flake-system.excludes = [
          den.policies.system-to-os-outputs
          den.policies.system-to-hm-outputs
        ];
        den.hosts.x86_64-linux.igloo.users = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = flakeTrace den "flake";
        expected = [
          (edge {
            source = collected "fleet=fleet" "nixos";
            target = outT [
              "flake"
              "nixosConfigurations"
              "igloo"
            ];
            mode = "merge";
            annotations = {
              resolvedRootVia = "scope-link";
              system = "x86_64-linux";
            };
          })
          (edge {
            source = collected "<root>" "homeManager";
            target = rootT "<root>" "homeManager";
            mode = "merge";
            annotations = {
              collectedScopes = [
                "<root>"
                "fleet=fleet"
                "host:igloo"
                "system=x86_64-linux"
              ];
            };
          })
          (edge {
            source = collected "<root>" "nixos";
            target = rootT "<root>" "nixos";
            mode = "merge";
            annotations = {
              collectedScopes = [
                "<root>"
                "fleet=fleet"
                "host:igloo"
                "system=x86_64-linux"
              ];
            };
          })
          # Per-host surfaced default folds (the instantiate projection).
          (edge {
            source = collected "host:igloo" "homeManager";
            target = rootT "host:igloo" "homeManager";
            mode = "merge";
            annotations = {
              collectedScopes = [ "host:igloo" ];
            };
          })
          (edge {
            source = collected "host:igloo" "nixos";
            target = rootT "host:igloo" "nixos";
            mode = "merge";
            annotations = {
              collectedScopes = [ "host:igloo" ];
            };
          })
          (edge {
            source = collected "host:igloo" "os";
            target = rootT "host:igloo" "nixos";
            mode = "merge";
          })
          (edge {
            source = collected "host:igloo" "os";
            target = rootT "host:igloo" "nixos";
            mode = "merge";
          })
        ];
      }
    );

    # ===== (3) microvm-guest-style isolated kind + verbatim route =====
    # Full list. The isolated guest gets its OWN default-fold edge (it is an
    # entity-root because isolated) — isolation = edge-absence: the guest's nixos
    # does NOT fold into the host root. The delivery route (reinstantiate=true,
    # appendToParent, collectSubtree) is nest-verbatim into the host root.
    test-topology-isolated-guest = denTest (
      { den, lib, ... }:
      let
        guestEntity = {
          name = "guest";
          system = "x86_64-linux";
          class = "nixos";
          intoAttr = [ ];
          users = { };
          aspect = den.aspects.guest-aspect;
        };
        deliverPolicy = den.lib.policy.mkPolicy "deliver-iso" (
          { ... }@args:
          lib.optionals (!(args ? user) && !(args ? home)) [
            (den.lib.policy.route {
              fromClass = "nixos";
              intoClass = "nixos";
              collectSubtree = true;
              appendToParent = true;
              reinstantiate = true;
              path = [
                "microvm"
                "vms"
                "guest"
              ];
            })
          ]
        );
      in
      {
        den.hosts.x86_64-linux.igloo.users = { };
        den.schema.iso-kind = {
          isEntity = true;
          parent = "host";
          isolated = true;
        };
        den.policies.resolve-iso-child =
          { host, ... }:
          lib.optionals (host.name == "igloo") [
            (den.lib.policy.resolve.to.withIncludes "iso-kind" [ deliverPolicy ] { iso-kind = guestEntity; })
          ];
        den.schema.host.includes = [ den.policies.resolve-iso-child ];
        den.aspects.guest-aspect.nixos.boot.kernelModules = [ "g" ];
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = hostTrace den "nixos" den.hosts.x86_64-linux.igloo;
        expected = [
          (edge {
            source = collected "host:igloo" "homeManager";
            target = rootT "host:igloo" "homeManager";
            mode = "merge";
            # The isolated guest scope is ABSENT from the host fold's collected
            # subtree — isolation as edge-absence (spec §2).
            annotations = {
              collectedScopes = [ "host:igloo" ];
            };
          })
          (edge {
            source = collected "host:igloo" "nixos";
            target = rootT "host:igloo" "nixos";
            mode = "merge";
            annotations = {
              collectedScopes = [ "host:igloo" ];
            };
          })
          (edge {
            source = collected "host:igloo" "os";
            target = rootT "host:igloo" "nixos";
            mode = "merge";
          })
          # Verbatim delivery route from the isolated guest subtree into the host.
          (edge {
            source = collected "host=igloo,iso-kind=guest" "nixos";
            target = rootT "host:igloo" "nixos";
            path = [
              "microvm"
              "vms"
              "guest"
            ];
            mode = "nest-verbatim";
            annotations = {
              appendToParent = true;
              collectSubtree = true;
            };
          })
          # The isolated guest's OWN default fold (it is its own entity-root).
          (edge {
            source = collected "host=igloo,iso-kind=guest" "nixos";
            target = rootT "host=igloo,iso-kind=guest" "nixos";
            mode = "merge";
            annotations = {
              collectedScopes = [ "host=igloo,iso-kind=guest" ];
            };
          })
        ];
      }
    );

    # ===== (4) standalone home (#605 synthetic host) ==================
    # Flake-level resolve of a standalone home → a homeConfigurations output
    # edge sourced from the system scope, the empty flake-root default folds,
    # AND the per-host (per-home) default folds the instantiate projection
    # surfaces (Task 18.2: the standalone home IS instantiated as a
    # homeConfigurations output, so its per-host fold edges are present). Full list.
    test-topology-standalone-home = denTest (
      { den, ... }:
      {
        den.homes.x86_64-linux.solo.homeManager.home.username = "solo";

        expr = flakeTrace den "flake";
        expected = [
          (edge {
            source = collected "system=x86_64-linux" "homeManager";
            target = outT [
              "flake"
              "homeConfigurations"
              "solo"
            ];
            mode = "merge";
            annotations = {
              resolvedRootVia = "scope-link";
              system = "x86_64-linux";
            };
          })
          (edge {
            source = collected "<root>" "homeManager";
            target = rootT "<root>" "homeManager";
            mode = "merge";
            annotations = {
              collectedScopes = [
                "<root>"
                "home:solo"
                "system=x86_64-linux"
              ];
            };
          })
          (edge {
            source = collected "<root>" "nixos";
            target = rootT "<root>" "nixos";
            mode = "merge";
            annotations = {
              collectedScopes = [
                "<root>"
                "home:solo"
                "system=x86_64-linux"
              ];
            };
          })
          # Per-home default folds (the instantiate projection's surfaced edges).
          (edge {
            source = collected "home:solo" "homeManager";
            target = rootT "home:solo" "homeManager";
            mode = "merge";
            annotations = {
              collectedScopes = [ "home:solo" ];
            };
          })
          (edge {
            source = collected "home:solo" "nixos";
            target = rootT "home:solo" "nixos";
            mode = "merge";
            annotations = {
              collectedScopes = [ "home:solo" ];
            };
          })
        ];
      }
    );

    # ===== (5) home-extraction (host-projected HM onto a user) ========
    # A host aspect projects homeManager content onto the user; the host-aspects
    # battery spawns the user home node. Subset+count assertion: this topology's
    # full list includes the user-forward tail and several default folds; the
    # mechanism under test is the host's homeManager default fold reaching the
    # user via the forward. We assert the user-forward synthesize edges are
    # present (the extraction edge) plus the total count.
    test-topology-home-extraction = denTest (
      { den, lib, ... }:
      let
        trace = hostTrace den "nixos" den.hosts.x86_64-linux.igloo;
        synthEdges = lib.filter (e: e.source ? synthesize) trace;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.homeManager.home.sessionVariables.X = "y";
        den.aspects.tux.includes = [ den.batteries.host-aspects ];

        expr = {
          # The HM-into-user forward (the extraction edge), targeting the user
          # root. Production (Task 18.2) captures the kept route only — the legacy
          # oracle's dedup-suppressed twin is absent.
          synth = synthEdges;
          # Stable total edge count for this topology.
          count = builtins.length trace;
        };
        expected = {
          synth = [
            (edge {
              source = synthesize "homeManager/nixos/home-manager/users/tux" "homeManager" "nixos";
              target = rootT "user:tux" "nixos";
              path = [
                "home-manager"
                "users"
                "tux"
              ];
              mode = "nest";
              annotations = {
                complexForward = true;
                sourceVia = "unresolved";
              };
            })
          ];
          count = 6;
        };
      }
    );

    # ===== (6) multi-system same-name (the @system arm) ===============
    # Two homes named `ben` on different systems → two homeConfigurations output
    # edges, each disambiguated to `ben@<system>`. Full list.
    test-topology-multi-system = denTest (
      { den, ... }:
      {
        den.homes.x86_64-linux.ben.homeManager.home.username = "ben";
        den.homes.aarch64-linux.ben.homeManager.home.username = "ben";

        expr = flakeTrace den "flake";
        expected = [
          (edge {
            source = collected "system=aarch64-linux" "homeManager";
            target = outT [
              "flake"
              "homeConfigurations"
              "ben@aarch64-linux"
            ];
            mode = "merge";
            annotations = {
              disambiguatedTo = "flake.homeConfigurations.ben@aarch64-linux";
              resolvedRootVia = "scope-link";
              system = "aarch64-linux";
            };
          })
          (edge {
            source = collected "system=x86_64-linux" "homeManager";
            target = outT [
              "flake"
              "homeConfigurations"
              "ben@x86_64-linux"
            ];
            mode = "merge";
            annotations = {
              disambiguatedTo = "flake.homeConfigurations.ben@x86_64-linux";
              resolvedRootVia = "scope-link";
              system = "x86_64-linux";
            };
          })
          (edge {
            source = collected "<root>" "homeManager";
            target = rootT "<root>" "homeManager";
            mode = "merge";
            annotations = {
              # Two distinct `ben` entities (different systems, distinct id_hashes
              # collapsing to the same readable name) both fold into the flake root.
              collectedScopes = [
                "<root>"
                "home:ben"
                "home:ben"
                "system=aarch64-linux"
                "system=x86_64-linux"
              ];
            };
          })
          (edge {
            source = collected "<root>" "nixos";
            target = rootT "<root>" "nixos";
            mode = "merge";
            annotations = {
              collectedScopes = [
                "<root>"
                "home:ben"
                "home:ben"
                "system=aarch64-linux"
                "system=x86_64-linux"
              ];
            };
          })
          # Per-home default folds (one pair per `ben` instantiate; the two homes
          # collapse to the same readable name but are distinct entity scopes).
          (edge {
            source = collected "home:ben" "homeManager";
            target = rootT "home:ben" "homeManager";
            mode = "merge";
            annotations = {
              collectedScopes = [ "home:ben" ];
            };
          })
          (edge {
            source = collected "home:ben" "nixos";
            target = rootT "home:ben" "nixos";
            mode = "merge";
            annotations = {
              collectedScopes = [ "home:ben" ];
            };
          })
          (edge {
            source = collected "home:ben" "homeManager";
            target = rootT "home:ben" "homeManager";
            mode = "merge";
            annotations = {
              collectedScopes = [ "home:ben" ];
            };
          })
          (edge {
            source = collected "home:ben" "nixos";
            target = rootT "home:ben" "nixos";
            mode = "merge";
            annotations = {
              collectedScopes = [ "home:ben" ];
            };
          })
        ];
      }
    );

    # ===== (7) darwin host (different class set) ======================
    # The default-fold class set is darwin (not nixos); the os→darwin route and
    # the homeManager→darwin user forward carry the darwin class. Full list.
    test-topology-darwin = denTest (
      { den, ... }:
      {
        den.hosts.aarch64-darwin.apple = {
          users.tux = { };
        };
        den.aspects.apple.nixos.networking.hostName = "apple";

        expr = hostTrace den "nixos" den.hosts.aarch64-darwin.apple;
        expected = [
          (edge {
            source = collected "host:apple" "darwin";
            target = rootT "host:apple" "darwin";
            mode = "merge";
            annotations = {
              collectedScopes = [
                "host:apple"
                "user:tux"
              ];
            };
          })
          (edge {
            source = collected "host:apple" "os";
            target = rootT "host:apple" "darwin";
            mode = "merge";
          })
          (edge {
            source = collected "host:apple" "homeManager";
            target = rootT "host:apple" "homeManager";
            mode = "merge";
            annotations = {
              collectedScopes = [
                "host:apple"
                "user:tux"
              ];
            };
          })
          (edge {
            source = collected "host:apple" "nixos";
            target = rootT "host:apple" "nixos";
            mode = "merge";
            annotations = {
              collectedScopes = [
                "host:apple"
                "user:tux"
              ];
            };
          })
          (edge {
            source = collected "user:tux" "os";
            target = rootT "user:tux" "darwin";
            mode = "merge";
          })
        ]
        ++ userForwardTail {
          user = "tux";
          os = "darwin";
        };
      }
    );

    # ===== (7b) spawn — NO rewalk edge at host level (Task 18.2) =======
    # The host-aspects battery on a user emits a deferred policy.spawn marker. The
    # LEGACY oracle (legacyEdgeTrace) renders that as a REWALK edge (the spawn
    # UNDERCOUNT). The PRODUCTION object (edgeTrace) drops the rewalk arm: at HOST
    # level the host is the ctx-seeded root (not a resolve.to-created entity scope
    # in scopeEntityKind), so the drain-fold spawn arm is a no-op — neither the
    # rewalk edge NOR a surfaced-spawn edge exists here. The surfaced-spawn edges
    # only appear at FLAKE level — which the fx-unified-edges and
    # fx-oracle-production-differential suites asserted until both were retired;
    # no suite asserts it today. So the production host trace carries NO
    # rewalk-source edge.
    test-topology-host-aspects-spawn = denTest (
      { den, lib, ... }:
      let
        trace = hostTrace den "nixos" den.hosts.x86_64-linux.igloo;
        spawnEdges = lib.filter (e: e.source ? rewalk) trace;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        # A host aspect projecting homeManager content (gives the spawned class
        # content; the spawn marker fires regardless of content).
        den.aspects.igloo.homeManager.home.sessionVariables.X = "y";
        den.aspects.tux.includes = [ den.batteries.host-aspects ];
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        # The production host trace has NO rewalk-source edge.
        expr = spawnEdges;
        expected = [ ];
      }
    );

    # ===== (8) fleet pipe value flowing through a delivery edge =======
    # A fleet-collected pipe (host-addrs) feeds a host nixos consumer, and the
    # host instantiate edge carries that into the flake output. Subset+count:
    # we assert the instantiate output edge (the delivery edge the pipe value
    # flows through) is present + the total count. The pipe VALUE itself is
    # config-level (not an edge property); this fixture pins that the delivery
    # topology is unchanged by pipe flow.
    test-topology-fleet-pipe = denTest (
      { den, lib, ... }:
      let
        trace = flakeTrace den "flake";
        outEdges = lib.filter (e: e.target ? output) trace;
      in
      {
        den.quirks.host-addrs.description = "addrs";
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
        den.policies.collect-addrs = _: [
          (den.lib.policy.pipe.from "host-addrs" [ (den.lib.policy.pipe.collectAll ({ host, ... }: true)) ])
        ];
        den.schema.flake.includes = [ den.policies.to-fleet ];
        den.schema.fleet.includes = [ den.policies.fleet-to-hosts ];
        den.schema.host.includes = [ den.policies.collect-addrs ];
        den.schema.flake-system.excludes = [
          den.policies.system-to-os-outputs
          den.policies.system-to-hm-outputs
        ];
        den.hosts.x86_64-linux.igloo.users = { };
        den.aspects.igloo.host-addrs =
          { host, ... }:
          {
            hostname = host.name;
          };
        den.aspects.igloo.nixos =
          { host-addrs, lib, ... }:
          {
            networking.extraHosts = lib.concatStringsSep "," (map (e: e.hostname) host-addrs);
          };

        expr = {
          outputs = outEdges;
          count = builtins.length trace;
        };
        expected = {
          # The host's flake-output delivery edge (pipe value flows through it).
          outputs = [
            (edge {
              source = collected "fleet=fleet" "nixos";
              target = outT [
                "flake"
                "nixosConfigurations"
                "igloo"
              ];
              mode = "merge";
              annotations = {
                resolvedRootVia = "scope-link";
                system = "x86_64-linux";
              };
            })
          ];
          # Production object (Task 18.2): the top-level folds + the per-host
          # surfaced fold/route edges the instantiate projection adds (the pipe
          # host-addrs class adds its own per-scope folds too).
          count = 9;
        };
      }
    );

    # ===== rule-corollary tests (spec §5.3) ===========================

    # Default-fold-edge existence: every entity-root scope with class content
    # has a merge edge collected(root, class) → (root, class), P=[].
    test-corollary-default-fold-exists = denTest (
      { den, lib, ... }:
      let
        trace = hostTrace den "nixos" den.hosts.x86_64-linux.igloo;
        hostFold = lib.filter (
          e:
          e.mode == "merge"
          && e.path == [ ]
          && e.source ? collected
          && e.source.collected.scope == "host:igloo"
          && e.source.collected.class == "nixos"
          && e.target ? root
          && e.target.root == "host:igloo"
          && e.target.class == "nixos"
        ) trace;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";
        expr = builtins.length hostFold;
        expected = 1;
      }
    );

    # Isolation-as-edge-absence: an isolated child contributes NO content to the
    # parent root's default fold. The host root fold COLLECTS from a subtree
    # (annotations.collectedScopes); isolation means the guest scope is ABSENT
    # from that set — the strongest available assertion (a default fold always
    # SOURCES from the root scope name, so a source-scope filter alone is
    # structurally vacuous; the collectedScopes membership has real teeth: if
    # subtreeScopesOf stopped honoring isolation, the guest scope would appear
    # here and the test goes red — verified by scratch-flipping the isolation
    # gate in subtreeScopesOf).
    test-corollary-isolation-edge-absence = denTest (
      { den, lib, ... }:
      let
        guestEntity = {
          name = "guest";
          system = "x86_64-linux";
          class = "nixos";
          intoAttr = [ ];
          users = { };
          aspect = den.aspects.guest-aspect;
        };
        guestScope = "host=igloo,iso-kind=guest";
        trace = hostTrace den "nixos" den.hosts.x86_64-linux.igloo;
        # The host root's nixos default fold (merge, P=[], sources+targets the
        # host root). Its collectedScopes is the isolation-aware subtree.
        hostNixosFold = lib.filter (
          e:
          e.mode == "merge"
          && e.path == [ ]
          && e.target ? root
          && e.target.root == "host:igloo"
          && e.target.class == "nixos"
          && e.source ? collected
          && e.source.collected.scope == "host:igloo"
          && e.source.collected.class == "nixos"
        ) trace;
        hostFoldScopes = (builtins.head hostNixosFold).annotations.collectedScopes;
        # The isolated guest's OWN fold (own entity-root), and its collected set.
        guestFold = lib.filter (
          e:
          e.mode == "merge"
          && e.path == [ ]
          && e.target ? root
          && e.target.root == guestScope
          && e.source ? collected
          && e.source.collected.scope == guestScope
        ) trace;
      in
      {
        den.hosts.x86_64-linux.igloo.users = { };
        den.schema.iso-kind = {
          isEntity = true;
          parent = "host";
          isolated = true;
        };
        den.policies.resolve-iso-child =
          { host, ... }:
          lib.optionals (host.name == "igloo") [
            (den.lib.policy.resolve.to "iso-kind" { iso-kind = guestEntity; })
          ];
        den.schema.host.includes = [ den.policies.resolve-iso-child ];
        den.aspects.guest-aspect.nixos.boot.kernelModules = [ "g" ];
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = {
          # Exactly one host nixos fold, and the guest scope is NOT in its
          # collected subtree (the isolation edge-absence).
          hostFoldExists = builtins.length hostNixosFold == 1;
          guestInHostFold = builtins.elem guestScope hostFoldScopes;
          # The guest's OWN fold exists and collects from ITSELF (it IS an
          # entity-root, so its subtree contains its own scope).
          guestOwnFold = builtins.length guestFold == 1;
          guestInOwnFold = builtins.elem guestScope (builtins.head guestFold).annotations.collectedScopes;
        };
        expected = {
          hostFoldExists = true;
          guestInHostFold = false;
          guestOwnFold = true;
          guestInOwnFold = true;
        };
      }
    );

    # Verbatim mode on a reinstantiate route.
    test-corollary-verbatim-mode = denTest (
      { den, lib, ... }:
      let
        guestEntity = {
          name = "guest";
          system = "x86_64-linux";
          class = "nixos";
          intoAttr = [ ];
          users = { };
          aspect = den.aspects.guest-aspect;
        };
        deliverPolicy = den.lib.policy.mkPolicy "deliver-iso" (
          { ... }@args:
          lib.optionals (!(args ? user) && !(args ? home)) [
            (den.lib.policy.route {
              fromClass = "nixos";
              intoClass = "nixos";
              collectSubtree = true;
              appendToParent = true;
              reinstantiate = true;
              path = [
                "microvm"
                "vms"
                "guest"
              ];
            })
          ]
        );
        trace = hostTrace den "nixos" den.hosts.x86_64-linux.igloo;
        verbatim = lib.filter (e: e.mode == "nest-verbatim") trace;
      in
      {
        den.hosts.x86_64-linux.igloo.users = { };
        den.schema.iso-kind = {
          isEntity = true;
          parent = "host";
          isolated = true;
        };
        den.policies.resolve-iso-child =
          { host, ... }:
          lib.optionals (host.name == "igloo") [
            (den.lib.policy.resolve.to.withIncludes "iso-kind" [ deliverPolicy ] { iso-kind = guestEntity; })
          ];
        den.schema.host.includes = [ den.policies.resolve-iso-child ];
        den.aspects.guest-aspect.nixos.boot.kernelModules = [ "g" ];
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = {
          count = builtins.length verbatim;
          path = (builtins.head verbatim).path;
        };
        expected = {
          count = 1;
          path = [
            "microvm"
            "vms"
            "guest"
          ];
        };
      }
    );

    # Suppression annotation ABSENT in the production object: the production edge
    # object (Task 18.2) CAPTURES the edges its fold dispatched (kept routes only),
    # so the legacy oracle's dedup-suppressed twin — which carried
    # `suppressed = true` — is never present. The suppressed twin lived in the
    # legacy re-derivation; that oracle and the
    # fx-oracle-production-differential suite that compared the two are both
    # retired, so nothing asserts the twin's shape now. This cell covers one
    # direction only: the production object's ABSENCE of the annotation.
    test-corollary-suppression-annotation = denTest (
      { den, lib, ... }:
      let
        trace = hostTrace den "nixos" den.hosts.x86_64-linux.igloo;
        suppressed = lib.filter (e: e.annotations.suppressed or false) trace;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";
        expr = builtins.length suppressed;
        expected = 0;
      }
    );

    # ===== stability: identical trace across two resolve calls =========
    test-stability-identical-across-runs = denTest (
      { den, ... }:
      let
        a = hostTrace den "nixos" den.hosts.x86_64-linux.igloo;
        b = hostTrace den "nixos" den.hosts.x86_64-linux.igloo;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";
        # Two independent resolves of the same config produce byte-identical
        # traces (sort applied; extraction pure).
        expr = a == b;
        expected = true;
      }
    );
  };
}
