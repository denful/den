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

  };
}
