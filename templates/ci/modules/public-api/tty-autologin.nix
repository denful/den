{ denTest, ... }:
{
  flake.tests.tty-autologin = {

    test-service-defined = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.aspects.igloo.includes = [ (den.provides.tty-autologin "root") ];

        expr = config.flake.nixosConfigurations.igloo.config.systemd.services ? "getty@tty1";
        expected = true;
      }
    );

    test-no-service-without-include = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };

        expr = config.flake.nixosConfigurations.igloo.config.systemd.services ? "getty@tty1";
        expected = false;
      }
    );

  };
}
