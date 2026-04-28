{ denTest, ... }:
{
  flake.tests.mutual-provider = {

    test-host-provide-user = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.policies.to-tux =
          { host, user, ... }:
          lib.optional (user.name == "tux") (include {
            homeManager.home.shellAliases.g = "git";
          });

        expr = igloo.home-manager.users.tux.home.shellAliases;

        expected.g = "git";
      }
    );

    test-user-provide-host = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.policies.to-igloo =
          { host, user, ... }:
          lib.optional (host.name == "igloo") (include {
            nixos.boot.crashDump.reservedMemory = "99999M";
          });

        expr = igloo.boot.crashDump.reservedMemory;

        expected = "99999M";
      }
    );

    test-provide-each-other = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.policies.to-tux =
          { host, user, ... }:
          lib.optional (user.name == "tux") (include {
            homeManager.home.keyboard.model = "denboard";
          });

        den.aspects.tux.policies.to-igloo =
          { host, user, ... }:
          lib.optional (host.name == "igloo") (include {
            nixos.boot.kernel.randstructSeed = "denseed";
          });

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
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.policies.to-users =
          { host, user, ... }:
          [
            (include {
              homeManager.home.keyboard.model = "denboard";
            })
          ];

        den.aspects.tux.policies.to-hosts =
          { host, user, ... }:
          [
            (include {
              nixos.boot.kernel.randstructSeed = "denseed@${host.name}";
            })
          ];

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
