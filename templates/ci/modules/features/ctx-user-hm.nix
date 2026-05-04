{ denTest, ... }:
{
  flake.tests.ctx-user-hm = {
    test-ctx-user-delivers-hm-stateversion = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        # Use deprecated den.ctx.user to set stateVersion (like the reporting user)
        den.ctx.user.homeManager.home.stateVersion = lib.mkForce "24.05";

        expr = tuxHm.home.stateVersion;
        expected = "24.05";
      }
    );
  };
}
