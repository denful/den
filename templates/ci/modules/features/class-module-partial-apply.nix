{ denTest, ... }:
{
  flake.tests.class-module-partial-apply = {

    # Flat form: a nixos class module that requests `host` (a den context arg)
    # alongside standard module-system args. wrapClassModule detects `host`
    # in __ctx and pre-applies it, so the module evaluates successfully.
    test-flat-form-host-accessible = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.test-flat.includes = [ ];

        den.policies.host-to-test-flat =
          _:
          let
            inherit (den.lib.policy) include;
          in
          [
            (include {
              nixos =
                { host, config, ... }:
                {
                  networking.hostName = host.name;
                };
            })
          ];

        den.schema.host.includes = [ den.policies.host-to-test-flat ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # Two-layer form: the existing curried pattern still works unchanged.
    # The outer function is parametric (resolved by den), the inner is a
    # standard NixOS module — no wrapping needed.
    test-two-layer-form-unchanged = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.test-twolayer.includes = [ ];

        den.policies.host-to-test-twolayer =
          _:
          let
            inherit (den.lib.policy) include;
          in
          [
            (include (
              { host, ... }:
              {
                nixos =
                  { config, ... }:
                  {
                    networking.hostName = host.name;
                  };
              }
            ))
          ];

        den.schema.host.includes = [ den.policies.host-to-test-twolayer ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # Multiple den args: both `host` and `user` are pre-applied from context.
    # The policy resolves with both host and user in the dispatch context,
    # so both are available for partial application in the class module.
    test-multiple-den-args = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.test-multi-args.includes = [ ];

        den.policies.host-to-test-multi-args =
          {
            host,
            ...
          }:
          let
            inherit (den.lib.policy) resolve include;
          in
          map (user: resolve.to "test-multi-args" { inherit user; }) (builtins.attrValues host.users)
          ++ [
            (include {
              nixos =
                {
                  host,
                  user,
                  config,
                  ...
                }:
                {
                  users.users.tux.description = "${host.name}/${user.name}";
                };
            })
          ];

        den.schema.host.includes = [ den.policies.host-to-test-multi-args ];

        expr = igloo.users.users.tux.description;
        expected = "igloo/tux";
      }
    );

    # Global collision policy config plumbing: verify den.config.classModuleCollisionPolicy
    # is settable and carries the configured value.
    test-global-collision-policy-plumbing = denTest (
      { den, ... }:
      {
        den.config.classModuleCollisionPolicy = "den-wins";

        expr = den.config.classModuleCollisionPolicy;
        expected = "den-wins";
      }
    );

    # Aspect meta.collisionPolicy is accessible through the aspect's meta.
    test-aspect-meta-collision-policy = denTest (
      { den, ... }:
      {
        den.aspects.test-cp = {
          meta.collisionPolicy = "class-wins";
        };

        expr = den.aspects.test-cp.meta.collisionPolicy;
        expected = "class-wins";
      }
    );

    # Functor module: an attrset with __functor passes through without wrapping
    # (builtins.isFunction returns false for functors). NixOS handles functors
    # natively, so the module still evaluates successfully.
    test-functor-module-passthrough = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.test-functor.includes = [ ];

        den.policies.host-to-test-functor =
          _:
          let
            inherit (den.lib.policy) include;
          in
          [
            (include {
              nixos = {
                __functor =
                  self:
                  { config, ... }:
                  {
                    networking.hostName = self.myName;
                  };
                myName = "from-functor";
              };
            })
          ];

        den.schema.host.includes = [ den.policies.host-to-test-functor ];

        expr = igloo.networking.hostName;
        expected = "from-functor";
      }
    );

    # functionArgs preservation: if the wrapped module evaluates successfully
    # through NixOS, setFunctionArgs worked — NixOS needs functionArgs to know
    # which args to pass. This is tested indirectly via the flat-form test above,
    # but we add an explicit test with a more complex arg pattern.
    test-function-args-preservation = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.test-funcargs.includes = [ ];

        den.policies.host-to-test-funcargs =
          _:
          let
            inherit (den.lib.policy) include;
          in
          [
            (include {
              nixos =
                {
                  host,
                  config,
                  lib,
                  pkgs,
                  ...
                }:
                {
                  users.users.tux.description = host.name;
                };
            })
          ];

        den.schema.host.includes = [ den.policies.host-to-test-funcargs ];

        expr = igloo.users.users.tux.description;
        expected = "igloo";
      }
    );

    # Entity-level collisionPolicy plumbing: host entity carries collisionPolicy
    # from the schema definition and it is accessible.
    test-entity-collision-policy-plumbing = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          collisionPolicy = "den-wins";
        };

        expr = den.hosts.x86_64-linux.igloo.collisionPolicy;
        expected = "den-wins";
      }
    );

    # Flat-form class module on a parametric aspect — the outer parametric
    # function receives host context, which propagates to __ctx, enabling
    # wrapClassModule to pre-apply host to the inner flat-form nixos module.
    test-flat-form-on-parametric-aspect = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.flat-aspect-test.includes = [
          (
            { host, ... }:
            {
              nixos =
                { host, config, ... }:
                {
                  networking.hostName = host.name;
                };
            }
          )
        ];
        den.aspects.igloo.includes = [ den.aspects.flat-aspect-test ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # Flat-form class module on a static (non-parametric) aspect included in
    # a dispatched stage. Context flows via __scopeHandlers to children.
    test-flat-form-on-static-aspect = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.static-flat = {
          nixos =
            { host, config, ... }:
            {
              networking.hostName = host.name;
            };
        };

        den.schema.test-static-flat.includes = [ ];

        den.policies.host-to-test-static-flat =
          _:
          let
            inherit (den.lib.policy) include;
          in
          [
            (include den.aspects.static-flat)
          ];

        den.schema.host.includes = [ den.policies.host-to-test-static-flat ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # Host-parametric aspect with user-parametric class — outer function
    # resolves host via den, inner class module requests user via wrapping.
    # Policy provides both host and user in context.
    test-host-parametric-user-class = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.test-cross-param.includes = [ ];

        den.policies.host-to-test-cross-param =
          {
            host,
            ...
          }:
          let
            inherit (den.lib.policy) resolve include;
          in
          map (user: resolve.to "test-cross-param" { inherit user; }) (builtins.attrValues host.users)
          ++ [
            (include (
              { host, ... }:
              {
                nixos =
                  { user, config, ... }:
                  {
                    users.users.tux.description = "${host.name}/${user.name}";
                  };
              }
            ))
          ];

        den.schema.host.includes = [ den.policies.host-to-test-cross-param ];

        expr = igloo.users.users.tux.description;
        expected = "igloo/tux";
      }
    );

    # Parenthesized two-layer form: { host }: ({ config, pkgs, ... }: {})
    # Parens are syntactically irrelevant in Nix. After parametric resolution,
    # the inner function is the class module with host captured via closure.
    test-parenthesized-two-layer = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.test-paren.includes = [ ];

        den.policies.host-to-test-paren =
          _:
          let
            inherit (den.lib.policy) include;
          in
          [
            (include (
              { host, ... }:
              {
                nixos = (
                  { config, ... }:
                  {
                    networking.hostName = host.name;
                  }
                );
              }
            ))
          ];

        den.schema.host.includes = [ den.policies.host-to-test-paren ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # Full application: nixos = { host }: ({ config, ... }: {})
    # All functionArgs are den args, so the function is called directly
    # instead of merged. The result (inner function) becomes the class module.
    test-full-application-curried = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.test-full-apply.includes = [ ];

        den.policies.host-to-test-full-apply =
          _:
          let
            inherit (den.lib.policy) include;
          in
          [
            (include {
              nixos =
                { host }:
                (
                  { config, ... }:
                  {
                    networking.hostName = host.name;
                  }
                );
            })
          ];

        den.schema.host.includes = [ den.policies.host-to-test-full-apply ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # Collision — error (default): unit test on the validator directly.
    # The validator receives moduleArgs with a colliding den arg and throws
    # inside its warnings when the error policy is active.
    test-collision-error-throws = denTest (
      { den, lib, ... }:
      let
        wrapClassModule = den.lib.aspects.fx.aspect.wrapClassModule;
        result = wrapClassModule {
          module =
            { host, config, ... }:
            {
              networking.hostName = host;
            };
          ctx = {
            host = "from-den";
          };
          aspectPolicy = null;
          globalPolicy = "error";
        };
        # Call the validator with a colliding host value via _module.args.
        # The validator throws inside warnings when error policy is active.
        validatorFn = lib.setFunctionArgs result.validator result.validatorAdvertisedArgs;
        validatorResult = validatorFn {
          config._module.args = {
            host = "from-specialArgs";
          };
        };
        # Force the warnings to trigger the throw.
        callResult = builtins.tryEval (builtins.deepSeq validatorResult.warnings true);
      in
      {
        expr = callResult.success;
        expected = false;
      }
    );

    # Collision — error integration: verify throw propagates through NixOS eval.
    # The validator throws inside config.warnings when it detects _module.args
    # collision with error policy. We use tryEval to observe the failure without
    # crashing nix-unit.
    test-collision-error-integration = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.test-collision-err-int.includes = [ ];

        den.policies.host-to-collision-err-int =
          _:
          let
            inherit (den.lib.policy) include;
          in
          [
            (include { nixos._module.args.host = "from-module-system"; })
            (include {
              nixos =
                { host, config, ... }:
                {
                  networking.hostName = if builtins.isString host then host else host.name;
                };
            })
          ];

        den.schema.host.includes = [ den.policies.host-to-collision-err-int ];

        # The throw from the validator propagates when any part of igloo
        # config that depends on warnings is accessed. tryEval catches it.
        expr = !(builtins.tryEval (builtins.seq igloo.warnings null)).success;
        expected = true;
      }
    );

    # Collision — den-wins via entity schema: den value wins over module-system.
    test-collision-den-wins = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.collisionPolicy = "den-wins";

        den.schema.test-collision-dw.includes = [ ];

        den.policies.host-to-collision-dw =
          _:
          let
            inherit (den.lib.policy) include;
          in
          [
            (include { nixos._module.args.host = "from-module-system"; })
            (include {
              nixos =
                { host, config, ... }:
                {
                  networking.hostName = if builtins.isString host then host else host.name;
                };
            })
          ];

        den.schema.host.includes = [ den.policies.host-to-collision-dw ];

        # Den value wins — host is the den entity, not the string.
        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # Collision — global config override: den.config.classModuleCollisionPolicy = "den-wins"
    test-collision-global-override = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.config.classModuleCollisionPolicy = "den-wins";

        den.schema.test-collision-global.includes = [ ];

        den.policies.host-to-collision-global =
          _:
          let
            inherit (den.lib.policy) include;
          in
          [
            (include { nixos._module.args.host = "from-module-system"; })
            (include {
              nixos =
                { host, config, ... }:
                {
                  networking.hostName = if builtins.isString host then host else host.name;
                };
            })
          ];

        den.schema.host.includes = [ den.policies.host-to-collision-global ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # Collision — class-wins via entity schema: module-system value wins.
    test-collision-class-wins = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.collisionPolicy = "class-wins";

        den.schema.test-collision-cw.includes = [ ];

        den.policies.host-to-collision-cw =
          _:
          let
            inherit (den.lib.policy) include;
          in
          [
            (include { nixos._module.args.host = "from-module-system"; })
            (include {
              nixos =
                { host, config, ... }:
                {
                  networking.hostName = if builtins.isString host then host else host.name;
                };
            })
          ];

        den.schema.host.includes = [ den.policies.host-to-collision-cw ];

        expr = igloo.networking.hostName;
        expected = "from-module-system";
      }
    );

  };
}
