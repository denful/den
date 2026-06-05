{ denTest, ... }:
{
  flake.tests.deadbugs-issue-292 = {

    test-should-not-read-from-host-without-mutuality = denTest (
      {
        den,
        lib,
        igloo, # igloo = nixosConfigurations.igloo.config
        tuxHm, # tuxHm = igloo.home-manager.users.tux
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.bash ];
        den.aspects.tux.includes = [ den.aspects.bash ];

        den.aspects.bash.homeManager.programs.bash.historyIgnore = [ "foo" ];

        expr = tuxHm.programs.bash.historyIgnore;
        expected = [ "foo" ];
      }
    );

  };
}
