{ denTest, ... }:
{
  flake.tests.home-manager-use-global-pkgs = {

    test-enabled = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # host entity includes are applied when host has HM support
        den.schema.host.includes = [
          { nixos.home-manager.useGlobalPkgs = true; }
        ];

        expr = igloo.home-manager.useGlobalPkgs;
        expected = true;
      }
    );

    test-disabled = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        expr = igloo.home-manager.useGlobalPkgs;
        expected = false;
      }
    );

    test-not-activated-without-hm-users = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.schema.hm-host.includes = [
          { nixos.home-manager.useGlobalPkgs = true; }
        ];

        expr = config.flake.nixosConfigurations.igloo.config ? home-manager;
        expected = false;
      }
    );

  };
}
