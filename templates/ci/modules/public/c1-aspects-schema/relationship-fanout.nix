# Synchronous relationship fan-out: a parametric aspect at scope S destructuring
# an entity-kind arg K_a that is a schema-DAG DESCENDANT of S's kind fans out
# over S's K_a-children, refiring bound to each, EMITTING AT S. Class content
# foreign to S (e.g. homeManager on a host scope) becomes inert.
#
# A misplaced entity arg (K_a neither in-ctx nor a descendant) → whole aspect
# inert, silently. Zero children → inert. Fan-out is synchronous inside `bind`;
# entity args never reach `defer`.
{ denTest, lib, ... }:
{
  flake.tests.relationship-fanout = {

    # 1. Per-user distinct content lands on the host once per user.
    test-per-user-distinct-lands-on-host = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.nixos.options.funny = lib.mkOption {
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };

        # { user } at host scope: user is a descendant of host → fan out.
        den.aspects.igloo.includes = [
          (
            { user, ... }:
            {
              nixos.funny = [ "nixos ${user.name}" ];
            }
          )
        ];

        expr = lib.sort lib.lessThan igloo.funny;
        expected = [
          "nixos pingu"
          "nixos tux"
        ];
      }
    );

    # 2. Dedup guard: identical STATIC content per user appears TWICE in the
    # merged list (the per-child __ctxId tag must keep the two fan-out instances
    # distinct so neither collapses).
    test-identical-static-appears-per-user = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.nixos.options.funny = lib.mkOption {
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };

        den.aspects.igloo.includes = [
          (
            { user, ... }:
            {
              nixos.funny = [ "static" ];
            }
          )
        ];

        expr = lib.sort lib.lessThan igloo.funny;
        expected = [
          "static"
          "static"
        ];
      }
    );

    # 3. homeManager content in a HOST-scope fan-out aspect is class-local to the
    # host (which does not resolve homeManager) → inert; it must NOT land on the
    # users' HM eval. The old cross-scope defer carrier is starved (entity args
    # bypass defer), so the leak is gone.
    test-homemanager-content-inert-at-host-scope = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.includes = [
          (
            { user, ... }:
            {
              homeManager.programs.direnv.enable = true;
            }
          )
        ];

        expr = [
          tuxHm.programs.direnv.enable
          pinguHm.programs.direnv.enable
        ];
        # Inert: host scope resolves no homeManager class. Users never receive it.
        expected = [
          false
          false
        ];
      }
    );

    # 4. Misplaced: a fresh entity kind with no parent, destructured at host
    # scope → inert, no error, host still evaluates.
    test-misplaced-entity-arg-inert = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.schema.gadget.isEntity = true;

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo = {
          nixos.networking.hostName = "igloo";
          includes = [
            (
              { gadget, ... }:
              {
                nixos.networking.hostName = "should-not-appear";
              }
            )
          ];
        };

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # 5. Zero children: host with no users + { user } aspect → inert, no error.
    test-zero-children-inert = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo = { };

        den.aspects.igloo = {
          nixos.networking.hostName = "igloo";
          includes = [
            (
              { user, ... }:
              {
                nixos.networking.hostName = "should-not-appear";
              }
            )
          ];
        };

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # 6. Composition of in-ctx + descendant: { host, user } at HOST scope. host is
    # in ctx (bound once), user is a descendant (fan-out). Per-user distinct
    # content carrying the bound host name lands on the host.
    test-host-in-ctx-user-descendant = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.nixos.options.funny = lib.mkOption {
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };

        den.aspects.igloo.includes = [
          (
            { host, user, ... }:
            {
              nixos.funny = [ "${user.name}@${host.name}" ];
            }
          )
        ];

        expr = lib.sort lib.lessThan igloo.funny;
        expected = [
          "pingu@igloo"
          "tux@igloo"
        ];
      }
    );

    # 7. Root-scope entity arg → INERT (carrier removed @ this commit; rule: root
    # entity arg → inert). The formal rule: a parametric entity arg at a scope
    # whose entity kind is NEITHER able to bind it from ctx NOR an ancestor of it
    # is misplaced → whole aspect inert, silently. The root (flake) scope has NO
    # entity kind, so a `{ user, ... }` aspect there is strictly inert.
    #
    # Root-scope path: top-level resolution starts at the `flake` entity
    # (modules/outputs.nix: resolveEntity "flake" {}), whose includes are
    # `den.schema.flake.includes` (flake is a non-entity routing kind). That
    # scope is the rootScopeId with NO scopeEntityKind entry, so bind.nix sees
    # scopeKind == null: isDescendantOf is false, the `user` arg is misplaced →
    # inert. Previously this rode the cross-scope defer carrier (push-scope
    # deferred inheritance + walkDeferred refire); that carrier is now removed.
    test-root-scope-descendant-arg-inert = denTest (
      {
        den,
        igloo,
        tuxHm,
        pinguHm,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.nixos.options.funny = lib.mkOption {
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };

        # { user } aspect at the ROOT (flake) scope — NOT host scope. Verified to
        # take the defer path (scopeKind == null), not the fan-out path.
        den.schema.flake.includes = [
          (
            { user, ... }:
            {
              nixos.funny = [ "root-saw ${user.name}" ];
              homeManager.programs.direnv.enable = true;
            }
          )
        ];

        expr = {
          hostFunny = lib.sort lib.lessThan igloo.funny;
          tuxDirenv = tuxHm.programs.direnv.enable;
          pinguDirenv = pinguHm.programs.direnv.enable;
        };
        # Inert: root scope has no entity kind, so the { user } aspect is
        # misplaced. Neither class is delivered to descendants.
        expected = {
          hostFunny = [ ];
          tuxDirenv = false;
          pinguDirenv = false;
        };
      }
    );

    # 8. Shared-include suppression: when the SAME source aspect is registered
    # into BOTH den.schema.host.includes AND den.schema.user.includes (the
    # den.default pattern), it reaches each user directly via the user scope's
    # own resolution. Fanning it out at the host scope too would double-cover.
    # `sharedWithDescendant` detects the shared provenance root (matching the
    # include node's identity.key against schema.user.includes) and makes the
    # aspect INERT at the host scope, so each user's contribution lands EXACTLY
    # once. If the suppression were broken, the list would be DOUBLED
    # (["shared pingu" "shared pingu" "shared tux" "shared tux"]).
    test-shared-include-suppresses-fanout = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.nixos.options.funny = lib.mkOption {
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };

        # A NAMED aspect carries a stable identity.key from any registration
        # site (a bare lambda would anonymize differently per site). Register
        # the SAME node into BOTH host and user includes (the den.default
        # shape).
        den.aspects.shared.includes = [
          (
            { user, ... }:
            {
              nixos.funny = [ "shared ${user.name}" ];
            }
          )
        ];

        # Same provenance root in both lists. At each user scope `user` is
        # in-ctx and it binds once, landing the per-user contribution. At the
        # host scope `user` is a descendant → it would fan out, but
        # sharedWithDescendant detects the shared user-include root and makes it
        # INERT here → no double-cover. Each contribution lands EXACTLY once.
        den.schema.host.includes = [ den.aspects.shared ];
        den.schema.user.includes = [ den.aspects.shared ];

        expr = lib.sort lib.lessThan igloo.funny;
        expected = [
          "shared pingu"
          "shared tux"
        ];
      }
    );

    # 9. Independent descendant branches → CARTESIAN product. `{ user, pet }` at
    # host: user and pet are BOTH direct descendants of host (siblings in the
    # DAG), so every user pairs with every pet. Emergent from the rule (bind
    # fans one descendant, recursion fans the other). Spec §3 "independent
    # descendant branches → cartesian product".
    test-cartesian-independent-descendants = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.schema.pet.isEntity = true;
        den.schema.pet.parent = "host";

        den.hosts.x86_64-linux.igloo = {
          users = {
            tux = { };
            pingu = { };
          };
          pets = {
            rex = {
              name = "rex";
            };
            fido = {
              name = "fido";
            };
          };
        };

        den.aspects.igloo.nixos.options.funny = lib.mkOption {
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };

        den.aspects.igloo.includes = [
          (
            { user, pet, ... }:
            {
              nixos.funny = [ "${user.name}-${pet.name}" ];
            }
          )
        ];

        expr = lib.sort lib.lessThan igloo.funny;
        expected = [
          "pingu-fido"
          "pingu-rex"
          "tux-fido"
          "tux-rex"
        ];
      }
    );

    # 10. Cartesian with one EMPTY branch → whole product inert (no error). The
    # host has users but zero pets, so `{ user, pet }` yields no pairs and emits
    # nothing. Negative twin of #9.
    test-cartesian-empty-branch-inert = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.schema.pet.isEntity = true;
        den.schema.pet.parent = "host";

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo = {
          nixos.networking.hostName = "igloo";
          includes = [
            (
              { user, pet, ... }:
              {
                nixos.networking.hostName = "should-not-appear";
              }
            )
          ];
        };

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # 11. TRANSITIVE descendant fan-out (DAG nesting). host -> pet -> toy.
    # `{ pet, toy }` at host: `pet` is a direct descendant (fan over host.pets);
    # `toy` is a descendant of `pet`, so for each fanned pet it fans over THAT
    # pet's toys (pet.toys), emitting at the host. Spec §3 "transitive descendants
    # follow DAG nesting". Requires fanning the intermediate (pet) before its
    # child (toy) and enumerating toy off the bound pet record, not the host.
    test-transitive-descendant-chain = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.schema.pet.isEntity = true;
        den.schema.pet.parent = "host";
        den.schema.toy.isEntity = true;
        den.schema.toy.parent = "pet";

        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          pets.rex = {
            name = "rex";
            toys = {
              ball = {
                name = "ball";
              };
              bone = {
                name = "bone";
              };
            };
          };
        };

        den.aspects.igloo.nixos.options.funny = lib.mkOption {
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };

        den.aspects.igloo.includes = [
          (
            { pet, toy, ... }:
            {
              nixos.funny = [ "${pet.name}/${toy.name}" ];
            }
          )
        ];

        expr = lib.sort lib.lessThan igloo.funny;
        expected = [
          "rex/ball"
          "rex/bone"
        ];
      }
    );

  };
}
