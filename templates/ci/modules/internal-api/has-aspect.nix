# End-to-end tests for entity.hasAspect organized by aspect shape.
# Every aspect-construction shape that has produced a regression
# (#408, #413, #423, #429) has a lock-in test here, so a future
# regression in parametric.nix or aspects/types.nix that affects any
# of those shapes fails a hasAspect test before it reaches user code.
#
# Note: `igloo` from denTest specialArgs is the resolved NixOS config
# (config.flake.nixosConfigurations.igloo.config), not the den host
# entity. The host entity — which is where `hasAspect` lives — is
# reached via `den.hosts.x86_64-linux.igloo`. Same for users:
# `den.hosts.x86_64-linux.igloo.users.tux`.
{ denTest, lib, ... }:
{
  flake.tests.has-aspect = {

    test-host-hasAspect-present-static = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.feature ];
        den.aspects.feature.nixos = { };

        # host.hasAspect is available because host imports
        # den.schema.conf which imports modules/context/has-aspect.nix.
        expr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.feature;
        expected = true;
      }
    );

    test-host-hasAspect-absent = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.nixos = { };
        den.aspects.unrelated.nixos = { };

        expr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.unrelated;
        expected = false;
      }
    );

    test-user-hasAspect-present = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # denTest's default is classes = ["homeManager"] for users.
        den.aspects.tux.includes = [ den.aspects.user-feature ];
        den.aspects.user-feature.homeManager = { };

        expr = den.hosts.x86_64-linux.igloo.users.tux.hasAspect den.aspects.user-feature;
        expected = true;
      }
    );

    test-hasAspect-forClass-explicit = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.feature ];
        den.aspects.feature.nixos = { };

        expr = den.hosts.x86_64-linux.igloo.hasAspect.forClass "nixos" den.aspects.feature;
        expected = true;
      }
    );

    test-hasAspect-forAnyClass = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.feature ];
        den.aspects.feature.nixos = { };

        expr = den.hosts.x86_64-linux.igloo.hasAspect.forAnyClass den.aspects.feature;
        expected = true;
      }
    );

    test-hasAspect-respects-tombstone = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.keep
          den.aspects.drop
        ];
        den.aspects.igloo.meta.handleWith = den.lib.aspects.fx.constraints.exclude den.aspects.drop;
        den.aspects.keep.nixos = { };
        den.aspects.drop.nixos = { };

        expr = {
          keep = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.keep;
          drop = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.drop;
        };
        expected = {
          keep = true;
          drop = false;
        };
      }
    );

    test-hasAspect-angle-bracket-equivalent = denTest (
      { den, __findFile, ... }:
      {
        _module.args.__findFile = den.lib.__findFile;

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.feature.nixos = { };
        den.aspects.igloo.includes = [ den.aspects.feature ];

        # <feature> sugar resolves to den.aspects.feature via __findFile.
        expr = {
          viaAttr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.feature;
          viaAngle = den.hosts.x86_64-linux.igloo.hasAspect <feature>;
        };
        expected = {
          viaAttr = true;
          viaAngle = true;
        };
      }
    );

    # ─── Group A: sanity completions ──────────────────────────────────

    test-A-hosts-hasAspect-self = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos = { };

        # Host reports its own root aspect as present.
        expr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.igloo;
        expected = true;
      }
    );

    test-A-hosts-hasAspect-chained-transitively = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.level1 ];
        den.aspects.level1.includes = [ den.aspects.level2 ];
        den.aspects.level2.includes = [ den.aspects.level3 ];
        den.aspects.level3.nixos = { };

        expr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.level3;
        expected = true;
      }
    );

    # ─── Group B: parametric contexts (regression locks) ──────────────

    # Baseline parametric parent with static child.
    test-B-present-via-parametric-parent = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.parent ];
        den.aspects.parent =
          { host, ... }:
          {
            includes = [ den.aspects.child ];
          };
        den.aspects.child.nixos = { };

        expr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.child;
        expected = true;
      }
    );

    # #423 regression shape — parametric parent with static sub-aspect.
    # If applyDeep regresses, role.provides.sub vanishes from the tree.
    test-B-present-via-static-sub-aspect-in-parametric-parent = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.role =
              { host, ... }:
              {
                includes = [ den.aspects.role.provides.sub ];
              };
          }
          {
            den.aspects.role.provides.sub.nixos.networking.networkmanager.enable = true;
          }
          {
            den.aspects.igloo.includes = [ den.aspects.role ];
          }
        ];

        expr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.role.provides.sub;
        expected = true;
      }
    );

    # #413 shape — parametric parent unconditionally includes a
    # bare-function provider sub-aspect. Exercises the applyDeep
    # inner-recursion + meta-carryover path.
    test-B-present-via-bare-function-sub-aspect = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.foo =
              { host, ... }:
              {
                includes = [ den.aspects.foo.provides.sub ];
              };
          }
          {
            den.aspects.foo.provides.sub =
              { host, ... }:
              {
                nixos.networking.networkmanager.enable = true;
              };
          }
          {
            den.aspects.igloo.includes = [ den.aspects.foo ];
          }
        ];

        expr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.foo.provides.sub;
        expected = true;
      }
    );

    test-B-absent-when-parametric-parent-omits = denTest (
      { den, lib, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.gated ];
        den.aspects.gated =
          { host, ... }:
          {
            includes = lib.optional (host.name == "other-host") den.aspects.conditional;
          };
        den.aspects.conditional.nixos = { };

        expr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.conditional;
        expected = false;
      }
    );

    # ─── Group C: factory functions ───────────────────────────────────

    # Factory-fn aspects have a stable aspectPath derived from their
    # declaration name and can be queried directly when referenced in
    # includes. Note: invoking the factory inline (`facter arg`)
    # produces an anonymous sibling aspect with a loc-derived name —
    # factory identity is NOT inherited by instances.
    test-C-factory-fn-aspect-present = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.facter = reportPath: {
          nixos.environment.variables.FACTER_REPORT = reportPath;
        };
        den.aspects.igloo.includes = [ den.aspects.facter ];

        expr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.facter;
        expected = true;
      }
    );

    # #408 / #429 shape — parametric function + static sibling merging.
    test-C-factory-fn-merged-with-static-sibling = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.mixed =
              { host, ... }:
              {
                nixos.environment.variables.MIXED_HOST = host.name;
              };
          }
          {
            den.aspects.mixed.nixos.environment.variables.MIXED_STATIC = "yes";
          }
          {
            den.aspects.igloo.includes = [ den.aspects.mixed ];
          }
        ];

        expr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.mixed;
        expected = true;
      }
    );

    # ─── Group D: provider sub-aspects ────────────────────────────────

    test-D-static-provider-sub-present = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.foo.provides.sub ];
        den.aspects.foo.provides.sub.nixos = { };

        expr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.foo.provides.sub;
        expected = true;
      }
    );

    # Function-bodied provider sub-aspect reached via direct inclusion
    # — exercises the applyDeep outer-result meta-carryover path.
    test-D-parametric-provider-sub-present = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.foo.provides.sub ];
        den.aspects.foo.provides.sub =
          { host, ... }:
          {
            nixos.environment.variables.FOO_SUB = host.name;
          };

        expr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.foo.provides.sub;
        expected = true;
      }
    );

    test-D-provider-sub-identity-distinct-from-homonym = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.bar.provides.foo ];
        den.aspects.bar.provides.foo.nixos = { };
        # `foo` also exists at top level — different aspectPath.
        den.aspects.foo.nixos = { };

        expr = {
          sub = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.bar.provides.foo;
          top = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.foo;
        };
        expected = {
          sub = true;
          top = false;
        };
      }
    );

    # ─── Group E: policyFn-injected aspects ───────────────────────────

    # policyFn-injected aspects deliver config but are NOT visible to
    # hasAspect (runs its own pipeline without parent policyFn state).
    # Test that direct includes on the user aspect are still visible.
    test-E-present-via-user-includes = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.includes = [ den.aspects.user-target ];
        den.aspects.user-target.homeManager = { };

        expr = den.hosts.x86_64-linux.igloo.users.tux.hasAspect den.aspects.user-target;
        expected = true;
      }
    );

    # policyFn-injected aspects on the user's own aspect ARE visible
    # to hasAspect because the user aspect's policies are registered
    # during the hasAspect pipeline run.
    test-E-present-via-user-policyFn = denTest (
      { den, lib, ... }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.policies.self-inject =
          { host, user, ... }:
          [
            (include {
              includes = [ den.aspects.user-target ];
            })
          ];
        den.aspects.tux.includes = [ den.aspects.tux.policies.self-inject ];
        den.aspects.user-target.homeManager = { };

        expr = den.hosts.x86_64-linux.igloo.users.tux.hasAspect den.aspects.user-target;
        expected = true;
      }
    );

    # Host-policyFn includes: not visible to user hasAspect (separate pipeline).
    test-E-host-policyFn-not-visible-to-user-hasAspect = denTest (
      { den, lib, ... }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.policies.to-users =
          { host, user, ... }:
          [
            (include {
              includes = [ den.aspects.user-target ];
            })
          ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.to-users ];
        den.aspects.user-target.homeManager = { };

        # Host policyFn includes ARE delivered (config works) but NOT
        # visible to hasAspect which runs its own pipeline.
        expr = den.hosts.x86_64-linux.igloo.users.tux.hasAspect den.aspects.user-target;
        expected = false;
      }
    );

    # User-aspect policyFn injecting host config IS visible to host hasAspect
    # because the user's policyFn fires during the host pipeline AND the
    # hasAspect pipeline (user aspect is part of host resolution via transition).
    test-E-present-via-user-to-hosts = denTest (
      { den, lib, ... }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.policies.to-hosts =
          { host, user, ... }:
          [
            (include {
              includes = [ den.aspects.host-target ];
            })
          ];
        den.aspects.tux.includes = [ den.aspects.tux.policies.to-hosts ];
        den.aspects.host-target.nixos = { };

        expr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.host-target;
        expected = true;
      }
    );

    # ─── Group F: meta.adapter interactions ───────────────────────────

    test-F-respects-substituteAspect = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.original ];
        den.aspects.igloo.meta.handleWith =
          den.lib.aspects.fx.constraints.substitute den.aspects.original den.aspects.replacement;
        den.aspects.original.nixos = { };
        den.aspects.replacement.nixos = { };

        expr = {
          original = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.original;
          replacement = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.replacement;
        };
        expected = {
          original = false;
          replacement = true;
        };
      }
    );

    # Two adapters at DIFFERENT levels, each tombstoning a direct child
    # of its own aspect. Nested-reaching does NOT work because
    # filterIncludes.tag only stamps a parent's adapter onto children
    # without their own adapter — children with adapters keep theirs.
    # This test exercises composition that works: each adapter affects
    # its own subtree.
    test-F-composes-at-different-levels = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # igloo's adapter tombstones root-sibling at its own level.
        den.aspects.igloo.includes = [
          den.aspects.parent
          den.aspects.root-sibling
        ];
        den.aspects.igloo.meta.handleWith = den.lib.aspects.fx.constraints.exclude den.aspects.root-sibling;

        # parent's adapter tombstones parent-sibling at its own level.
        den.aspects.parent.includes = [
          den.aspects.child-a
          den.aspects.parent-sibling
        ];
        den.aspects.parent.meta.handleWith =
          den.lib.aspects.fx.constraints.exclude den.aspects.parent-sibling;

        den.aspects.root-sibling.nixos = { };
        den.aspects.parent-sibling.nixos = { };
        den.aspects.child-a.nixos = { };

        # Each adapter tombstones its own direct-child target;
        # child-a survives under parent.
        expr = {
          rootSibling = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.root-sibling;
          parentSibling = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.parent-sibling;
          childA = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.child-a;
        };
        expected = {
          rootSibling = false;
          parentSibling = false;
          childA = true;
        };
      }
    );

    # ─── Group G: multi-class users ───────────────────────────────────

    test-G-user-hasAspect-primary-class = denTest (
      { den, lib, ... }:
      {
        den.schema.user.classes = lib.mkForce [
          "user"
          "homeManager"
        ];
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.includes = [ den.aspects.target ];
        den.aspects.target.user = { };
        den.aspects.target.homeManager = { };

        # Primary class = lib.head classes = "user"
        expr = den.hosts.x86_64-linux.igloo.users.tux.hasAspect den.aspects.target;
        expected = true;
      }
    );

    test-G-user-hasAspect-forClass-explicit = denTest (
      { den, lib, ... }:
      {
        den.schema.user.classes = lib.mkForce [
          "user"
          "homeManager"
        ];
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.includes = [ den.aspects.target ];
        den.aspects.target.homeManager = { };

        expr = {
          user = den.hosts.x86_64-linux.igloo.users.tux.hasAspect.forClass "user" den.aspects.target;
          hm = den.hosts.x86_64-linux.igloo.users.tux.hasAspect.forClass "homeManager" den.aspects.target;
        };
        # Structural tree is class-invariant — both return true.
        expected = {
          user = true;
          hm = true;
        };
      }
    );

    test-G-user-hasAspect-forAnyClass-matches-any = denTest (
      { den, lib, ... }:
      {
        den.schema.user.classes = lib.mkForce [
          "user"
          "homeManager"
        ];
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.includes = [ den.aspects.target ];
        den.aspects.target.homeManager = { };

        expr = den.hosts.x86_64-linux.igloo.users.tux.hasAspect.forAnyClass den.aspects.target;
        expected = true;
      }
    );

    test-G-user-hasAspect-forClass-unknown-class = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.includes = [ den.aspects.target ];
        den.aspects.target.homeManager = { };

        # Unknown class: returns false silently, no error.
        expr = den.hosts.x86_64-linux.igloo.users.tux.hasAspect.forClass "bogus" den.aspects.target;
        expected = false;
      }
    );

    # ─── Group H: extensibility ───────────────────────────────────────

    # Verify den.schema.conf owns the hasAspect option — not
    # host/user/home individually. Any entity kind importing conf
    # inherits hasAspect.
    test-H-conf-option-exists = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # If conf owns the option, host imports conf, and therefore
        # host.hasAspect is defined. The smoke test would fail first
        # if not — this test documents the contract explicitly.
        expr = den.schema ? conf;
        expected = true;
      }
    );

    # ─── Group H2: nested freeform aspect refs ─────────────────────────

    # Nested aspects accessed via freeform key traversal (e.g.,
    # den.aspects.disk.zfs-disk-single) lack name/meta but carry
    # __provider. hasAspect must resolve these via __provider chain.
    test-H2-nested-freeform-present = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.parent.child ];
        den.aspects.parent.child.nixos = { };

        expr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.parent.child;
        expected = true;
      }
    );

    test-H2-nested-freeform-absent = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.nixos = { };
        den.aspects.parent.child.nixos = { };

        expr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.parent.child;
        expected = false;
      }
    );

    # Full provenance: den.aspects.a.sub and den.aspects.b.sub are distinct.
    # hasAspect must match the full path (a/sub vs b/sub), not just the leaf name.
    test-H2-nested-freeform-provenance-distinct = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.a.sub ];
        den.aspects.a.sub.nixos = { };
        den.aspects.b.sub.nixos = { };

        expr = {
          a-sub = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.a.sub;
          b-sub = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.b.sub;
        };
        expected = {
          a-sub = true;
          b-sub = false;
        };
      }
    );

    # Deeply nested freeform ref (3 levels).
    test-H2-deeply-nested-freeform = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.disk.zfs.single ];
        den.aspects.disk.zfs.single.nixos = { };

        expr = den.hosts.x86_64-linux.igloo.hasAspect den.aspects.disk.zfs.single;
        expected = true;
      }
    );

    # ─── Group I: error cases ─────────────────────────────────────────

    test-I-bad-ref-throws = denTest (
      { den, ... }:
      let
        result = builtins.tryEval (den.hosts.x86_64-linux.igloo.hasAspect "not-a-ref");
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos = { };

        expr = result.success;
        expected = false;
      }
    );

    # ─── Group J: real-world class-body call (cycle-safety check) ─────

    # The primary intended use case: calling hasAspect from inside a
    # deferred nixos module body. The body runs at evalModules time,
    # long after the aspect tree is frozen — a cyclic implementation
    # would hit infinite recursion here.
    #
    # Note: the `host` specialArg set by nix/lib/types.nix lives on
    # the den host submodule and does NOT propagate into OS-level
    # deferred nixos modules. We close over the entity at the outer
    # level via a let binding — the nixos body is still deferred, so
    # the cycle-safety property is still validated.
    test-J-hasAspect-in-class-module-body = denTest (
      { den, igloo, ... }:
      let
        hostEntity = den.hosts.x86_64-linux.igloo;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.feature-flag
          den.aspects.gated-consumer
        ];
        den.aspects.feature-flag.nixos = { };

        den.aspects.gated-consumer.nixos =
          { config, ... }:
          {
            environment.variables.HAS_FLAG =
              if hostEntity.hasAspect den.aspects.feature-flag then "yes" else "no";
          };

        expr = igloo.environment.variables.HAS_FLAG or null;
        expected = "yes";
      }
    );

  };
}
