{ denTest, ... }:
{
  flake.tests.default-includes = {

    test-setting-host-service-package = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.nixos =
          { pkgs, ... }:
          {
            services.locate.package = pkgs.plocate;
          };

        expr = lib.getName igloo.services.locate.package;
        expected = "plocate";
      }
    );

    test-set-hostname-from-host-context = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ den.provides.hostname ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    test-homemanager-applies-to-all-users = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.homeManager.programs.fish.enable = true;

        expr = [
          tuxHm.programs.fish.enable
          pinguHm.programs.fish.enable
        ];
        expected = [
          true
          true
        ];
      }
    );

    test-dynamic-class-in-user-host-context = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [
          (
            { user, host, ... }:
            {
              ${host.class}.users.users.${user.userName}.description = "${user.userName} on ${host.name}";
            }
          )
        ];

        expr = igloo.users.users.tux.description;
        expected = "tux on igloo";
      }
    );

  };
}
