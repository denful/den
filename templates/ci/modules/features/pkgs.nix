{ denTest, ... }:
{
  flake.tests.pkgs = {

    test-pkgs-set-on-host = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ (den._.pkgs (pkgs: pkgs.discord)) ];

        expr = igloo.config.environment.systemPackages;
        expected = [ "discord" ];
      }
    );

    test-pkgs-set-on-user = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.includes = [ (den._.pkgs (pkgs: pkgs.discord)) ];

        expr = igloo.config.users.users.tux.packages;
        expected = [ "discord" ];
      }
    );

    test-pkgs-set-on-home-manager = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [ (den._.pkgs (pkgs: pkgs.discord)) ];

        expr = tuxHm.config.home.packages;
        expected = [ "discord" ];
      }
    );

    test-pkgs-to-host-set-on-host = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.includes = [ (den._.pkgs._.to-host (pkgs: pkgs.discord)) ];

        expr = igloo.config.environment.systemPackages;
        expected = [ "discord" ];
      }
    );

    test-pkgs-to-user-set-on-user = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.includes = [ (den._.pkgs._.to-user (pkgs: pkgs.discord)) ];

        expr = igloo.config.users.users.tux.packages;
        expected = [ "discord" ];
      }
    );

    test-pkgs-to-home-set-on-home-manager = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [ (den._.pkgs._.to-home (pkgs: pkgs.discord)) ];

        expr = tuxHm.config.home.packages;
        expected = [ "discord" ];
      }
    );

  };
}
