{ denTest, ... }:
{
  flake.tests.mutual-provider = {

    test-host-provide-user = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.user.includes = [ den.provides.mutual-provider ];

        den.aspects.igloo.provides.tux = den.lib.parametric {
          homeManager.home.shellAliases.g = "git";
        };

        expr = igloo.home-manager.users.tux.home.shellAliases;

        expected.g = "git";
      }
    );

    test-user-provide-host = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.user.includes = [ den.provides.mutual-provider ];

        den.aspects.tux.provides.igloo = den.lib.parametric {
          nixos.boot.crashDump.reservedMemory = "99999M";
        };

        expr = igloo.boot.crashDump.reservedMemory;

        expected = "99999M";
      }
    );

    test-provide-each-other = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.user.includes = [ den.provides.mutual-provider ];

        den.aspects.igloo.provides.tux = den.lib.parametric {
          homeManager.home.keyboard.model = "denboard";
        };

        den.aspects.tux.provides.igloo = den.lib.parametric {
          nixos.boot.kernel.randstructSeed = "denseed";
        };

        expr = [
          igloo.boot.kernel.randstructSeed
          igloo.home-manager.users.tux.home.keyboard.model
        ];

        expected = [
          "denseed"
          "denboard"
        ];
      }
    );

    test-for-all = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.user.includes = [ den.provides.mutual-provider ];

        den.aspects.igloo.provides.to-users = {
          homeManager.home.keyboard.model = "denboard";
        };

        den.aspects.tux.provides.to-hosts =
          { host, ... }:
          {
            nixos.boot.kernel.randstructSeed = "denseed@${host.name}";
          };

        expr = [
          igloo.boot.kernel.randstructSeed
          igloo.home-manager.users.tux.home.keyboard.model
        ];

        expected = [
          "denseed@igloo"
          "denboard"
        ];
      }
    );

  };
}
