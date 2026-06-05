{ denTest, inputs, ... }:
{

  flake.tests.special-args-custom-instantiate = {

    test-standalone-hm-os-config = denTest (
      { den, config, ... }:
      {

        den.hosts.x86_64-linux.igloo = { };

        den.homes.x86_64-linux.pingu = {
          instantiate =
            { pkgs, modules }:
            inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs modules;
              extraSpecialArgs.osConfig = config.flake.nixosConfigurations.igloo.config;
            };
        };

        den.default.homeManager.home.stateVersion = "25.11";

        den.aspects.igloo.nixos.programs.vim.enable = true;
        den.aspects.pingu.homeManager =
          { osConfig, ... }:
          {
            programs.emacs.enable = osConfig.programs.vim.enable;
          };

        den.aspects.pingu.includes = [ den.provides.define-user ];

        expr = config.flake.homeConfigurations.pingu.config.programs.emacs.enable;
        expected = true;

      }
    );

  };

}
