# Regression: schema.hm-host includes with homeManager class keys are not
# forwarded into the home-manager config.  The nixos class works because it
# emits directly at the host scope, but homeManager content is stranded at
# the host scope with no route — it needs to enter user sub-scopes where
# the userForward route carries it to home-manager.users.<name>.
{ denTest, ... }:
{
  flake.tests.hm-host-forward-hm-class = {

    # homeManager key in hm-host schema should reach user's HM config
    test-hm-host-forwards-homemanager-class = denTest (
      {
        den,
        igloo,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.hm-host.includes = [
          {
            nixos.services.openssh.enable = true;
            homeManager.programs.vim.enable = true;
          }
        ];

        expr = {
          ssh = igloo.services.openssh.enable;
          vim = tuxHm.programs.vim.enable;
        };
        expected = {
          ssh = true;
          vim = true;
        };
      }
    );

    # Multiple users should each receive the homeManager content
    test-hm-host-forwards-hm-to-all-users = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.igloo.users.pingu = { };

        den.schema.hm-host.includes = [
          { homeManager.programs.vim.enable = true; }
        ];

        expr = {
          tux = igloo.home-manager.users.tux.programs.vim.enable;
          pingu = igloo.home-manager.users.pingu.programs.vim.enable;
        };
        expected = {
          tux = true;
          pingu = true;
        };
      }
    );

  };
}
