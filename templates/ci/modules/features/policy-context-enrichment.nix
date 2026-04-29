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

    test-mixed-resolve-split = denTest (
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

        den.aspects.user-check = {
          nixos =
            {
              isNixos,
              user,
              lib,
              ...
            }:
            lib.optionalAttrs isNixos {
              users.users.${user.name}.shell = "/bin/zsh";
            };
        };

        den.aspects.igloo.includes = [ den.aspects.user-check ];

        expr = igloo.users.users.tux.shell;
        expected = "/bin/zsh";
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

        den.aspects.host-env = {
          nixos =
            {
              isNixos,
              lib,
              ...
            }:
            lib.optionalAttrs isNixos {
              environment.variables.ENRICHED = "yes";
            };
        };

        den.aspects.igloo.includes = [ den.aspects.host-env ];

        expr = igloo.environment.variables.ENRICHED;
        expected = "yes";
      }
    );

    test-enrichment-optional-default = denTest (
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

        den.aspects.optional-enrich = {
          nixos =
            {
              isNixos ? false,
              lib,
              ...
            }:
            lib.optionalAttrs isNixos {
              environment.variables.TEST = "enriched";
            };
        };

        den.aspects.igloo.includes = [ den.aspects.optional-enrich ];

        expr = igloo.environment.variables.TEST;
        expected = "enriched";
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

    test-enrichment-with-traits = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.traits.firewall = {
          description = "Firewall rules";
          collection = "list";
        };

        den.policies.host-guards =
          { host, ... }:
          [
            (den.lib.policy.resolve {
              isNixos = host.class == "nixos";
            })
          ];

        den.aspects.netstack = {
          firewall = {
            port = 80;
          };
          nixos =
            {
              isNixos,
              lib,
              ...
            }:
            lib.optionalAttrs isNixos {
              services.openssh.enable = true;
            };
        };

        den.aspects.igloo.includes = [ den.aspects.netstack ];

        expr = igloo.services.openssh.enable;
        expected = true;
      }
    );

  };
}
