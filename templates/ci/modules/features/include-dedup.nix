{
  denTest,
  lib,
  ...
}:
{
  flake.tests.include-dedup = {

    # === Fix 1: Parametric merge — coerce to includes instead of last-wins ===

    # Two modules produce bare parametric fns at same provides path.
    # Before fix: lib.last → only 1 fn survives (count 0).
    # After fix: both coerced to includes (count 2).
    test-parametric-wrapper-merge = denTest (
      { den, ... }:
      let
        merged = den.aspects.parent.provides.shared;
      in
      {
        imports = [
          {
            den.aspects.parent.provides.shared =
              { user, ... }:
              {
                nixos.a = 1;
              };
          }
          {
            den.aspects.parent.provides.shared =
              { user, ... }:
              {
                nixos.b = 2;
              };
          }
        ];
        den.aspects.parent.includes = [ ];

        expr = builtins.length (merged.includes or [ ]);
        expected = 2;
      }
    );

    # Mixed fn + attrset at same top-level aspect path — regression guard.
    # The existing mergeMixed path coerces fns to includes. Should still work.
    test-mixed-parametric-and-attrset = denTest (
      { den, ... }:
      let
        aspect = den.aspects.mixed-test;
      in
      {
        imports = [
          {
            den.aspects.mixed-test =
              { user, ... }:
              {
                nixos.a = 1;
              };
          }
          { den.aspects.mixed-test.nixos.b = 2; }
        ];

        # fn coerced to include (1 entry), attrset nixos.b merged in.
        expr = builtins.length (aspect.includes or [ ]);
        expected = 1;
      }
    );

    # Two modules define __functor at same aspect — should error (ambiguous).
    # Before fix: lib.last silently wins (result true). After fix: throws.
    # NOTE: uses expectedError; nix-unit crashes if this eval-errors without
    # matching the expected shape, so we gate with tryEval for now.
    test-functor-conflict-errors = denTest (
      { den, ... }:
      let
        result = builtins.tryEval (builtins.deepSeq den.aspects.factory true);
      in
      {
        imports = [
          {
            den.aspects.factory = {
              __functor = self: args: self // { x = args; };
              includes = [ ];
            };
          }
          {
            den.aspects.factory = {
              __functor = self: args: self // { y = args; };
              includes = [ ];
            };
          }
        ];

        # Before fix: tryEval succeeds (no error). After fix: tryEval fails.
        expr = result.success;
        expected = false;
      }
    );

    # === Fix 2: Include-level dedup ===

    # Static aspect included via two parents — resolved once, 1 class emission.
    test-dedup-static-aspect-two-parents = denTest (
      { den, ... }:
      let
        shared = {
          name = "shared";
          meta = { };
          nixos = {
            networking.hostName = "test";
          };
          includes = [ ];
        };
        parentA = {
          name = "parentA";
          meta = { };
          includes = [ shared ];
        };
        parentB = {
          name = "parentB";
          meta = { };
          includes = [ shared ];
        };
        root = {
          name = "root";
          meta = { };
          includes = [
            parentA
            parentB
          ];
        };
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          self = root;
          ctx = { };
        };
      in
      {
        # Without dedup: 2 imports. With dedup: 1 import.
        expr = builtins.length (result.state.imports null);
        expected = 1;
      }
    );

    # Parametric class module, same context, included via two parents.
    test-dedup-parametric-class-two-parents = denTest (
      { den, ... }:
      let
        shared = {
          name = "shared";
          meta = { };
          nixos =
            { config, ... }:
            {
              networking.hostName = "test";
            };
          includes = [ ];
        };
        parentA = {
          name = "parentA";
          meta = { };
          includes = [ shared ];
        };
        parentB = {
          name = "parentB";
          meta = { };
          includes = [ shared ];
        };
        root = {
          name = "root";
          meta = { };
          includes = [
            parentA
            parentB
          ];
        };
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          self = root;
          ctx = { };
        };
      in
      {
        expr = builtins.length (result.state.imports null);
        expected = 1;
      }
    );

    # Same aspect with different __ctxId values — both should resolve (no dedup).
    test-no-dedup-different-contexts = denTest (
      { den, ... }:
      let
        sharedBase = {
          name = "shared";
          meta = { };
          nixos = {
            x = 1;
          };
          includes = [ ];
        };
        root = {
          name = "root";
          meta = { };
          includes = [
            (sharedBase // { __ctxId = "{host1,user1}"; })
            (sharedBase // { __ctxId = "{host2,user2}"; })
          ];
        };
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          self = root;
          ctx = { };
        };
      in
      {
        # Different contexts → different dedup keys → both resolve.
        expr = builtins.length (result.state.imports null);
        expected = 2;
      }
    );

    # Trait emission from shared aspect — collected once, not doubled.
    test-dedup-trait-two-parents = denTest (
      { den, ... }:
      let
        shared = {
          name = "shared";
          meta = { };
          firewall = {
            port = 80;
          };
          includes = [ ];
        };
        parentA = {
          name = "parentA";
          meta = { };
          includes = [ shared ];
        };
        parentB = {
          name = "parentB";
          meta = { };
          includes = [ shared ];
        };
        root = {
          name = "root";
          meta = { };
          includes = [
            parentA
            parentB
          ];
        };
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          self = root;
          ctx = { };
        };
      in
      {
        den.traits.firewall = {
          description = "Firewall rules";
          collection = "list";
        };

        # Without dedup: [{port=80;} {port=80;}]. With dedup: [{port=80;}].
        expr = builtins.length ((result.state.traits null).firewall or [ ]);
        expected = 1;
      }
    );

    # Aspect excluded by first parent, included by second — resolves on second visit.
    # Exclusion must not pollute includeSeen.
    test-excluded-then-included = denTest (
      { den, ... }:
      let
        shared = {
          name = "shared";
          meta.provider = [ ];
          nixos = {
            x = 1;
          };
          includes = [ ];
        };
        excluder = {
          name = "excluder";
          meta = {
            excludes = [ shared ];
          };
          includes = [ shared ];
        };
        treeA = {
          name = "treeA";
          meta = { };
          includes = [ excluder ];
        };
        treeB = {
          name = "treeB";
          meta = { };
          includes = [ shared ];
        };
        root = {
          name = "root";
          meta = { };
          includes = [
            treeA
            treeB
          ];
        };
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          self = root;
          ctx = { };
        };
      in
      {
        # shared excluded in treeA, included in treeB → 1 import.
        # If exclude pollutes includeSeen (bug): 0 imports.
        expr = builtins.length (result.state.imports null);
        expected = 1;
      }
    );

    # === Fix 3: Unsatisfied class module guard ===

    # Class module requests { user, ... }: but no user context — guard skips emission.
    test-guard-skips-without-context = denTest (
      { den, ... }:
      let
        aspect = {
          name = "nix-trusted";
          meta = { };
          nixos =
            {
              user,
              config,
              ...
            }:
            {
              nix.settings.trusted-users = [ user ];
            };
          includes = [ ];
        };
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          self = aspect;
          ctx = { };
        };
      in
      {
        # Before fix: 1 (module passes through unwrapped).
        # After fix: 0 (unsatisfied guard skips emission).
        expr = builtins.length (result.state.imports null);
        expected = 0;
      }
    );

    # Same module with user context via __scopeHandlers — wraps and emits.
    # Produces 2 imports: wrapped main module + collision validator.
    test-guard-defers-then-emits = denTest (
      { den, ... }:
      let
        handlers = den.lib.aspects.fx.handlers;
        aspect = {
          name = "nix-trusted";
          meta = { };
          nixos =
            {
              user,
              config,
              ...
            }:
            {
              nix.settings.trusted-users = [ user ];
            };
          includes = [ ];
          __scopeHandlers = handlers.constantHandler { user = "tux"; };
        };
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          self = aspect;
          ctx = {
            user = "tux";
          };
        };
      in
      {
        # With user context: module wraps (main + validator) → 2 imports.
        expr = builtins.length (result.state.imports null);
        expected = 2;
      }
    );

    # === Class-key merge (existing behavior, new coverage) ===

    # Two modules set same class key with same signature — both contribute
    # via aspectContentType merge (visible as imports list).
    test-same-class-key-same-signature-merges = denTest (
      { den, ... }:
      {
        imports = [
          {
            den.aspects.merged.nixos =
              {
                user,
                config,
                ...
              }:
              {
                a = true;
              };
          }
          {
            den.aspects.merged.nixos =
              {
                user,
                config,
                ...
              }:
              {
                b = true;
              };
          }
        ];
        den.aspects.merged.includes = [ ];

        expr = builtins.length (den.aspects.merged.nixos.imports or [ ]);
        expected = 2;
      }
    );

    # Two modules set same class key with different signatures — both contribute.
    test-same-class-key-different-signatures-merges = denTest (
      { den, ... }:
      {
        imports = [
          {
            den.aspects.multi-sig.nixos =
              {
                host,
                config,
                ...
              }:
              {
                a = true;
              };
          }
          {
            den.aspects.multi-sig.nixos =
              {
                user,
                config,
                ...
              }:
              {
                b = true;
              };
          }
        ];
        den.aspects.multi-sig.includes = [ ];

        expr = builtins.length (den.aspects.multi-sig.nixos.imports or [ ]);
        expected = 2;
      }
    );

  };
}
