{ denTest, ... }:
{
  flake.tests.host-aspects-sibling-leak = {
    # Host with two users; only `tux` opts into host-aspects. `pingu` must NOT
    # receive the host's homeManager projection.
    test-sibling-no-leak = denTest (
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
        den.aspects.igloo.homeManager.programs.vim.enable = true;
        den.aspects.tux.includes = [ den._.host-aspects ];
        # pingu does NOT include host-aspects
        expr = {
          tux = tuxHm.programs.vim.enable or false;
          pingu = pinguHm.programs.vim.enable or false;
        };
        expected = {
          tux = true;
          pingu = false;
        };
      }
    );
  };
}
