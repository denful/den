{ denTest, ... }:
{
  flake.tests.flat-hosts = {
    test-flat-host-two-level-shape = denTest (
      { den, ... }:
      {
        den.hosts.igloo = {
          system = "x86_64-linux";
          users.tux = { };
        };

        expr = builtins.attrNames den.hosts;
        expected = [ "x86_64-linux" ];
      }
    );

    test-flat-host-name = denTest (
      { den, ... }:
      {
        den.hosts.igloo = {
          system = "x86_64-linux";
          users.tux = { };
        };

        expr = den.hosts.x86_64-linux.igloo.name;
        expected = "igloo";
      }
    );

    test-flat-host-system = denTest (
      { den, ... }:
      {
        den.hosts.igloo = {
          system = "x86_64-linux";
          users.tux = { };
        };

        expr = den.hosts.x86_64-linux.igloo.system;
        expected = "x86_64-linux";
      }
    );

    test-flat-host-coexists-with-legacy = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.legacy-host.users.tux = { };
        den.hosts.flat-host = {
          system = "x86_64-linux";
          users.tux = { };
        };

        expr = builtins.sort (a: b: a < b) (builtins.attrNames den.hosts.x86_64-linux);
        expected = [
          "flat-host"
          "legacy-host"
        ];
      }
    );

    test-flat-host-users-with-module-args = denTest (
      { den, ... }:
      {
        den.hosts.igloo = {
          system = "x86_64-linux";
          users.tux = { };
        };

        expr = den.hosts.x86_64-linux.igloo.users.tux.host.name;
        expected = "igloo";
      }
    );

    test-flat-host-nixos-output = denTest (
      { den, igloo, ... }:
      {
        den.hosts.igloo = {
          system = "x86_64-linux";
          users.tux = { };
        };
        den.aspects.igloo.nixos.networking.hostName = "flat-test";

        expr = igloo.networking.hostName;
        expected = "flat-test";
      }
    );
  };
}
