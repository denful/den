{ denTest, ... }:
{

  flake.tests.home-manager-managed-home = {

    test-program-enabled = denTest (
      {
        den,
        lib,
        config,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.homeManager.programs.vim.enable = true;

        expr = tuxHm.programs.vim.enable;
        expected = true;
      }
    );

    test-homedir-defined = denTest (
      {
        den,
        lib,
        config,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.provides.define-user ];

        expr = tuxHm.home.homeDirectory;
        expected = "/home/tux";
      }
    );

  };

}
