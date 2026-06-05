{ denTest, ... }:
{
  flake.tests.nested-class-module-args = {

    # Guard: class module with { user } skipped when user not in context
    test-guard-skips-without-context = denTest (
      {
        den,
        config,
        ...
      }:
      {
        den.hosts.x86_64-linux.x1c.users.pol = { };

        den.aspects.tools.provides.nix-trusted-user = {
          includes = [
            {
              nixos =
                { user, ... }:
                {
                  nix.settings.trusted-users = [ user.userName ];
                };
            }
          ];
        };

        # benix includes nix-trusted-user but has no user context
        den.aspects.benix = {
          includes = [
            den.aspects.tools.provides.nix-trusted-user
          ];
          nixos.users.users.benix.isNormalUser = true;
        };

        # pol includes both directly and via benix
        den.aspects.pol.includes = [
          den.provides.define-user
          den.aspects.tools.provides.nix-trusted-user
          den.aspects.benix
        ];

        # Should not error — guard skips benix's emission of { user }
        # Pipeline correctly deduplicates across include paths
        expr = config.flake.nixosConfigurations.x1c.config.nix.settings.trusted-users;
        expected = [
          "root"
          "pol"
        ];
      }
    );

    # Dedup: same aspect included via two parents should emit class once
    test-dedup-same-aspect-two-parents = denTest (
      {
        den,
        config,
        ...
      }:
      {
        den.hosts.x86_64-linux.x1c.users.pol = { };

        den.aspects.shared-setting = {
          nixos.networking.hostName = "from-shared";
        };

        den.aspects.bundle-a = {
          includes = [ den.aspects.shared-setting ];
        };

        den.aspects.bundle-b = {
          includes = [ den.aspects.shared-setting ];
        };

        den.aspects.x1c.includes = [
          den.aspects.bundle-a
          den.aspects.bundle-b
        ];

        # shared-setting emits nixos class from two paths — should dedup
        expr = config.flake.nixosConfigurations.x1c.config.networking.hostName;
        expected = "from-shared";
      }
    );

    # Dedup: parametric class module included via two parents
    test-dedup-parametric-class-two-parents = denTest (
      {
        den,
        config,
        ...
      }:
      {
        den.hosts.x86_64-linux.x1c.users.pol = { };

        den.aspects.trusted-user =
          { user, ... }:
          {
            nixos.nix.settings.trusted-users = [ user.userName ];
          };

        den.aspects.security.includes = [ den.aspects.trusted-user ];
        den.aspects.base.includes = [ den.aspects.trusted-user ];

        den.aspects.pol.includes = [
          den.provides.define-user
          den.aspects.security
          den.aspects.base
        ];

        # Same parametric aspect resolves with same { user=pol } from two parents
        # BUG: produces [ "root" "pol" "pol" ] — should be [ "root" "pol" ]
        expr = config.flake.nixosConfigurations.x1c.config.nix.settings.trusted-users;
        expected = [
          "root"
          "pol"
        ];
      }
    );

  };
}
