{ denTest, ... }:
{
  flake.tests.policy-context-enrichment = {

    # Policy emits non-schema resolve bindings (isDarwin/isNixos).
    # A parametric wrapper aspect should defer until the bindings arrive,
    # then resolve with the enriched context.
    test-parametric-wrapper-defers-for-policy-context = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.host-guards =
          { host, ... }:
          [
            (den.lib.policy.resolve {
              isNixos = host.class == "nixos";
              isDarwin = host.class == "darwin";
            })
          ];

        den.default.includes = [ den.policies.host-guards ];

        den.aspects.gpg-agent =
          { isNixos }:
          {
            nixos = { lib, ... }: lib.optionalAttrs isNixos { services.openssh.enable = true; };
          };

        den.aspects.igloo.includes = [ den.aspects.gpg-agent ];

        expr = igloo.services.openssh.enable;
        expected = true;
      }
    );

    # Flat-form class module requests a policy-injected context arg
    # directly in the class module function signature. The pipeline
    # should defer the class module until the policy enriches context.
    test-flat-form-class-defers-for-policy-context = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.host-guards =
          { host, ... }:
          [
            (den.lib.policy.resolve {
              isNixos = host.class == "nixos";
              isDarwin = host.class == "darwin";
            })
          ];

        den.default.includes = [ den.policies.host-guards ];

        den.aspects.wayprompt = {
          nixos =
            { isNixos, lib, ... }:
            lib.optionalAttrs isNixos {
              services.openssh.enable = true;
            };
        };

        den.aspects.igloo.includes = [ den.aspects.wayprompt ];

        expr = igloo.services.openssh.enable;
        expected = true;
      }
    );

    # Non-schema resolve bindings with isDarwin=true on a darwin host
    # should make the condition work in the other direction.
    test-policy-context-darwin-branch = denTest (
      { den, config, ... }:
      {
        den.hosts.aarch64-darwin.apple = { };

        den.policies.host-guards =
          { host, ... }:
          [
            (den.lib.policy.resolve {
              isNixos = host.class == "nixos";
              isDarwin = host.class == "darwin";
            })
          ];

        den.default.includes = [ den.policies.host-guards ];

        den.aspects.apple = {
          darwin =
            { isDarwin, lib, ... }:
            lib.optionalAttrs isDarwin {
              system.defaults.dock.autohide = true;
            };
        };

        expr = config.flake.darwinConfigurations.apple.config.system.defaults.dock.autohide;
        expected = true;
      }
    );

    # Mixed resolve: schema key (user) + non-schema key (isNixos) in same
    # resolve call.  The schema key should create a child entity transition,
    # the non-schema key should enrich the current context.
    test-mixed-resolve-split = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.mixed =
          {
            host,
            ...
          }:
          let
            inherit (den.lib.policy) resolve include;
          in
          map (
            user:
            resolve {
              inherit user;
              isNixos = host.class == "nixos";
            }
          ) (builtins.attrValues host.users)
          ++ [
            (include den.aspects.user-check)
          ];

        den.schema.host.includes = [ den.policies.mixed ];

        den.aspects.user-check = {
          nixos =
            {
              isNixos,
              user,
              lib,
              ...
            }:
            lib.optionalAttrs isNixos {
              environment.variables.MIXED_USER = user.name;
            };
        };

        expr = igloo.environment.variables.MIXED_USER;
        expected = "tux";
      }
    );

    test-enrichment-chained-policies = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.host-guards =
          { host, ... }:
          [
            (den.lib.policy.resolve {
              isNixos = host.class == "nixos";
            })
          ];

        den.policies.platform-info =
          { isNixos, ... }:
          [
            (den.lib.policy.resolve {
              platform = if isNixos then "linux" else "other";
            })
          ];

        den.default.includes = [
          den.policies.host-guards
          den.policies.platform-info
        ];

        den.aspects.platform-test =
          { platform }:
          {
            nixos =
              { lib, ... }:
              {
                environment.variables.PLATFORM = platform;
              };
          };

        den.aspects.igloo.includes = [ den.aspects.platform-test ];

        expr = igloo.environment.variables.PLATFORM;
        expected = "linux";
      }
    );

    # Enrichment + user fan-out coexist.  Class module takes both isNixos
    # (enrichment) and user (fan-out) in the same function signature.
    # Should fire once per user with correct values for both.
    test-enrichment-fan-out = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          alice = { };
          bob = { };
        };

        den.policies.host-guards =
          { host, ... }:
          [
            (den.lib.policy.resolve {
              isNixos = host.class == "nixos";
            })
          ];

        den.policies.user-routing =
          {
            host,
            ...
          }:
          let
            inherit (den.lib.policy) resolve include;
          in
          map (user: resolve { inherit user; }) (builtins.attrValues host.users)
          ++ [
            (include den.aspects.user-config)
          ];

        den.default.includes = [
          den.policies.host-guards
          den.policies.user-routing
        ];

        den.aspects.user-config = {
          nixos =
            {
              isNixos,
              user,
              lib,
              ...
            }:
            lib.optionalAttrs (isNixos && user.name == "alice") {
              environment.variables.ALICE_PRESENT = "yes";
            };
        };

        expr = igloo.environment.variables.ALICE_PRESENT;
        expected = "yes";
      }
    );

    # Module requests an arg no policy ever provides.
    # Should use the default value, not crash or infinite-recurse.
    test-enrichment-never-provided = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.noop = {
          nixos =
            {
              neverProvided ? "default",
              lib,
              ...
            }:
            {
              environment.variables.TEST = neverProvided;
            };
        };

        den.aspects.igloo.includes = [ den.aspects.noop ];

        expr = igloo.environment.variables.TEST;
        expected = "default";
      }
    );

    test-enrichment-multiple-policies = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.host-guards =
          { host, ... }:
          [
            (den.lib.policy.resolve {
              isNixos = host.class == "nixos";
            })
          ];

        den.policies.feature-flags =
          { host, ... }:
          [
            (den.lib.policy.resolve {
              enableBluetooth = true;
            })
          ];

        den.default.includes = [
          den.policies.host-guards
          den.policies.feature-flags
        ];

        den.aspects.bt-config =
          { isNixos, enableBluetooth }:
          {
            nixos =
              { lib, ... }:
              lib.optionalAttrs (isNixos && enableBluetooth) {
                hardware.bluetooth.enable = true;
              };
          };

        den.aspects.igloo.includes = [ den.aspects.bt-config ];

        expr = igloo.hardware.bluetooth.enable;
        expected = true;
      }
    );

    test-static-class-module-unchanged = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.host-guards =
          { host, ... }:
          [
            (den.lib.policy.resolve {
              isNixos = host.class == "nixos";
            })
          ];

        den.default.includes = [ den.policies.host-guards ];

        den.aspects.static-config = {
          nixos = {
            services.openssh.enable = true;
          };
        };

        den.aspects.igloo.includes = [ den.aspects.static-config ];

        expr = igloo.services.openssh.enable;
        expected = true;
      }
    );

    # Regression: fully-applied class modules (all args are den args,
    # no remaining module-system args) are plain attrsets. The post-pipeline
    # stripping must not call lib.setFunctionArgs on them — that injects
    # __functionArgs into the config, crashing the module system.
    # Regression: fully-applied class modules (all args are den args,
    # no remaining module-system args) produce plain attrsets with
    # wrapped=true.  Post-pipeline stripping must not call
    # lib.setFunctionArgs on plain attrsets — that injects
    # __functionArgs into the config, crashing the module system.
    test-fully-applied-hm-no-functionargs-leak = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.host-guards =
          { host, ... }:
          [
            (den.lib.policy.resolve {
              isDarwin = host.class == "darwin";
              isNixos = host.class == "nixos";
            })
          ];

        den.default.includes = [ den.policies.host-guards ];

        # Parametric wrapper with only den args → fully applied.
        # The inner homeManager value is a plain attrset.
        den.aspects.jujutsu =
          { isNixos }:
          {
            homeManager.programs.fish.enable = true;
          };

        den.aspects.igloo.includes = [ den.aspects.jujutsu ];

        # If __functionArgs leaks, this crashes with:
        # "The option `__functionArgs' does not exist"
        # Just verify no crash — the parametric wrapper defers until
        # enrichment provides isNixos, then fully applies.
        expr = igloo.networking.hostName;
        expected = "nixos";
      }
    );

  };
}
