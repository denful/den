{ den, ... }:
{
  # --- Home-level role aspects (composed into alice's home) ---

  # Dev role: git + bat configuration for the home environment.
  den.aspects.home-dev = {
    includes = [
      den.aspects.home-git
      den.aspects.home-bat
    ];
  };

  den.aspects.home-git = {
    homeManager =
      { ... }:
      {
        programs.git = {
          enable = true;
          userName = "Alice";
          userEmail = "alice@example.com";
        };
      };
  };

  den.aspects.home-bat = {
    homeManager =
      { ... }:
      {
        programs.bat = {
          enable = true;
          config.theme = "catppuccin-mocha";
        };
      };
  };

  # Productivity role: firefox + slack for the home environment.
  den.aspects.home-productivity = {
    includes = [
      den.aspects.home-firefox
      den.aspects.home-slack
    ];
  };

  den.aspects.home-firefox = {
    homeManager =
      { ... }:
      {
        programs.firefox.enable = true;
      };
  };

  den.aspects.home-slack = {
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.slack ];
      };
  };

  # Dotfiles: shell customization, only fires in home contexts.
  den.aspects.alice-dotfiles = {
    homeManager =
      { ... }:
      {
        programs.starship.enable = true;
      };
  };

  # --- Alice user aspect ---

  den.aspects.alice = {
    includes = [
      den.batteries.primary-user
      den.aspects.demo-shell
      den.aspects.hyprland
      den.aspects.dev-tools
      # Home-level roles: only materialize in home contexts.
      (den.lib.perHome den.aspects.home-dev)
      (den.lib.perHome den.aspects.home-productivity)
      (den.lib.perHome den.aspects.alice-dotfiles)
    ];
    nixos =
      { ... }:
      {
        users.users.alice.isNormalUser = true;
      };
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.git ];
      };

    # Cross-provides: alice provides SSH config to every host she's on.
    provides.to-hosts.nixos.users.users.alice.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA... alice@example"
    ];
  };
}
