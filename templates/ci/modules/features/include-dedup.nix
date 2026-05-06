{
  denTest,
  lib,
  ...
}:
{
  flake.tests.include-dedup = {

    # === Fix 1: Parametric merge — coerce to includes instead of last-wins ===

    # Two modules produce { host, ... }: fns at same top-level aspect.
    # coercedProviderType coerces each to { includes = [fn]; }, merged additively.
    # Both resolve with host context and contribute to igloo config.
    test-parametric-wrapper-merge = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.shared-cfg =
              { host, ... }:
              {
                nixos.environment.variables.PARAM_A = host.name;
              };
          }
          {
            den.aspects.shared-cfg =
              { host, ... }:
              {
                nixos.environment.variables.PARAM_B = "from-b";
              };
          }
        ];
        den.aspects.igloo.includes = [ den.aspects.shared-cfg ];

        expr = {
          a = igloo.environment.variables.PARAM_A or "missing";
          b = igloo.environment.variables.PARAM_B or "missing";
        };
        expected = {
          a = "igloo";
          b = "from-b";
        };
      }
    );

    # Two modules produce { host, ... }: fns at same provides path.
    # Tests the providerType.merge multi-def path (Fix 1 target).
    # Before fix: lib.last → only second fn. After fix: both coerced to includes.
    test-provides-parametric-merge = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.prov-parent.provides.shared-prov =
              { host, ... }:
              {
                nixos.environment.variables.PROV_A = host.name;
              };
          }
          {
            den.aspects.prov-parent.provides.shared-prov =
              { host, ... }:
              {
                nixos.environment.variables.PROV_B = "from-b";
              };
          }
        ];
        den.aspects.prov-parent.includes = [ ];
        den.aspects.igloo.includes = [ den.aspects.prov-parent.provides.shared-prov ];

        expr = {
          a = igloo.environment.variables.PROV_A or "missing";
          b = igloo.environment.variables.PROV_B or "missing";
        };
        expected = {
          a = "igloo";
          b = "from-b";
        };
      }
    );

    # Mixed fn + attrset at same top-level aspect path — regression guard.
    # The existing mergeMixed path coerces fns to includes. Should still work.
    test-mixed-parametric-and-attrset = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.igloo =
              { host, ... }:
              {
                nixos.environment.variables.MIX_HOST = host.name;
              };
          }
          { den.aspects.igloo.nixos.environment.variables.MIX_STATIC = "yes"; }
        ];

        expr = {
          host = igloo.environment.variables.MIX_HOST or "missing";
          static = igloo.environment.variables.MIX_STATIC or "missing";
        };
        expected = {
          host = "igloo";
          static = "yes";
        };
      }
    );

    # Two modules define __functor at same aspect — error on conflicting defs.
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

        # Multiple __functor at same path → error.
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
        expr = builtins.length (
          (builtins.foldl' (
            acc: sd:
            lib.zipAttrsWith (_: builtins.concatLists) [
              acc
              sd
            ]
          ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
        );
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
        expr = builtins.length (
          (builtins.foldl' (
            acc: sd:
            lib.zipAttrsWith (_: builtins.concatLists) [
              acc
              sd
            ]
          ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
        );
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
        # Non-context-dependent aspects with same content dedup even
        # across different __ctxId values — __ctxId is stripped from
        # the class-collector dedup identity since it doesn't affect
        # the module output.
        expr = builtins.length (
          (builtins.foldl' (
            acc: sd:
            lib.zipAttrsWith (_: builtins.concatLists) [
              acc
              sd
            ]
          ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
        );
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
        expr = builtins.length (
          (builtins.foldl' (
            acc: sd:
            lib.zipAttrsWith (_: builtins.concatLists) [
              acc
              sd
            ]
          ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
        );
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
        result = den.lib.aspects.fx.pipeline.fxResolve {
          class = "nixos";
          self = aspect;
          ctx = { };
        };
      in
      {
        # Without user context: unsatisfied module skipped → 0 imports.
        expr = builtins.length result.imports;
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
        result = den.lib.aspects.fx.pipeline.fxResolve {
          class = "nixos";
          self = aspect;
          ctx = {
            user = "tux";
          };
        };
      in
      {
        # With user context: module wraps (main + validator) → 2 imports.
        expr = builtins.length result.imports;
        expected = 2;
      }
    );

    # === Class-key merge (existing behavior, new coverage) ===

    # Two modules set same class key with same signature — both contribute
    # via aspectContentType merge. Verified end-to-end through NixOS eval.
    test-same-class-key-same-signature-merges = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };

        imports = [
          {
            den.aspects.igloo.nixos =
              { config, ... }:
              {
                environment.variables.TEST_A = "a";
              };
          }
          {
            den.aspects.igloo.nixos =
              { config, ... }:
              {
                environment.variables.TEST_B = "b";
              };
          }
        ];

        expr = {
          a = igloo.environment.variables.TEST_A or "missing";
          b = igloo.environment.variables.TEST_B or "missing";
        };
        expected = {
          a = "a";
          b = "b";
        };
      }
    );

    # Two modules set same class key with different signatures — both contribute.
    test-same-class-key-different-signatures-merges = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };

        imports = [
          {
            den.aspects.igloo.nixos =
              { lib, config, ... }:
              {
                environment.variables.FROM_LIB = "yes";
              };
          }
          {
            den.aspects.igloo.nixos =
              { config, ... }:
              {
                environment.variables.FROM_CONFIG = "yes";
              };
          }
        ];

        expr = {
          fromLib = igloo.environment.variables.FROM_LIB or "missing";
          fromConfig = igloo.environment.variables.FROM_CONFIG or "missing";
        };
        expected = {
          fromLib = "yes";
          fromConfig = "yes";
        };
      }
    );

    # Provide with anonymous parametric sub-includes setting a unique-typed
    # option. The entity resolves twice (first from host scope, second from
    # self-referential policy dispatch). Both resolutions walk the provide's
    # sub-includes. The second resolution must NOT produce duplicate modules
    # with different identities — that would collide on the unique option.
    # Reproduces: slashfiles inputs' _module.args collision.
    test-provide-anon-sub-include-no-dup = denTest (
      {
        den,
        lib,
        igloo,
        tuxHm,
        ...
      }:
      let
        # Mimics den.provides.inputs' pattern: a provide with anonymous
        # parametric sub-includes that emit to homeManager class.
        myProvide = {
          name = "my-provide";
          meta = { };
          includes = [
            # osAspect — parametric, takes { host }
            (
              { host }:
              {
                ${host.class}.environment.variables.FROM_PROVIDE = "yes";
              }
            )
            # userAspect — parametric, takes { user, host }, emits to homeManager
            (
              { user, host }:
              {
                homeManager.home.sessionVariables.FROM_PROVIDE = "yes";
              }
            )
          ];
        };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";
        den.policies.enrichment =
          { host, ... }:
          [
            (den.lib.policy.resolve {
              isNixos = host.class == "nixos";
            })
          ];
        den.default.includes = [
          myProvide
          # Enrichment policy — mimics slashfiles host-guards which adds
          # isDarwin/isNixos context. This triggers context widening and
          # re-dispatch at each entity scope, causing the provide's sub-includes
          # to be walked a second time with different __ctxId.
          den.policies.enrichment
        ];

        expr = {
          nixos = igloo.environment.variables.FROM_PROVIDE or "missing";
          hm = tuxHm.home.sessionVariables.FROM_PROVIDE or "missing";
        };
        expected = {
          nixos = "yes";
          hm = "yes";
        };
      }
    );

  };
}
