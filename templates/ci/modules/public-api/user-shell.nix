{ denTest, ... }:
{

  flake.tests.user-shell.test-on-nixos-included-at-user = denTest (
    {
      den,
      lib,
      igloo,
      tuxHm,
      ...
    }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.default.homeManager.home.stateVersion = "25.11";
      den.aspects.tux.includes = [ (den.provides.user-shell "fish") ];
      expr = {
        defaultShell = igloo.users.users.tux.shell.pname;
        osFish = igloo.programs.fish.enable;
        hmFish = tuxHm.programs.fish.enable;
      };
      expected = {
        defaultShell = "fish";
        osFish = true;
        hmFish = true;
      };
    }
  );

}
