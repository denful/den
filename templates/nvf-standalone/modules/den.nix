{
  inputs,
  den,
  lib,
  ...
}:
{
  imports = [
    inputs.den.flakeModule
    inputs.den.flakeOutputs.packages
  ];

  den.schema.flake-system.includes = [ den.aspects.flake ];

  den.aspects.flake.packages =
    { pkgs, ... }:
    let
      # custom den.lib.nvf from ./nvf-integration.nix
      nvf = den.lib.nvf.package pkgs;
    in
    {
      my-neovim = nvf den.aspects.my-neovim { mine = true; };
      your-neovim = nvf den.aspects.my-neovim { mine = false; };
    };

  den.aspects.my-neovim =
    { mine }:
    {
      vim =
        { pkgs, ... }:
        {
          theme.enable = true;
          theme.name = "catppuccin";
          theme.style = if mine then "frappe" else "latte";

          extraPackages = [
            pkgs.ripgrep
            pkgs.fd
            pkgs.fzf
          ];

          # nvf.vim.options
          opts = {
            expandtab = true;
            tabstop = 2;
            shiftwidth = 2;
            wrap = false;
          };
        };

      includes = [ den.aspects.nvf ];
    };

  den.aspects.nvf = {

    includes = with den.aspects.nvf.provides; [
      leader
      keys
      which-key
      snacks
      lazy
    ];

    provides.keys.vim.keymaps = [
      {
        key = "<leader><leader>";
        mode = [ "n" ];
        desc = "Smart find";
        action = "function() Snacks.picker.smart() end";
        lua = true;
      }
      {
        key = "<leader>,";
        mode = [ "n" ];
        desc = "Buffers";
        action = "function() Snacks.picker.buffers() end";
        lua = true;
      }
      {
        key = "<leader>/";
        mode = [ "n" ];
        desc = "Grep";
        action = "function() Snacks.picker.grep() end";
        lua = true;
      }
      {
        key = "<leader>:";
        mode = [ "n" ];
        desc = "Command history";
        action = "function() Snacks.picker.command_history() end";
        lua = true;
      }
    ];

    provides.leader.vim.globals = {
      mapleader = " ";
      maplocalleader = " ";
    };

    provides.which-key.vim.binds.whichKey = {
      enable = true;
      setupOpts = {
        delay = 550;
        preset = "helix";
        keys = {
          scroll_up = "<c-p>";
          scroll_down = "<c-n>";
        };
      };
    };

    provides.lazy.vim =
      { pkgs, ... }:
      {
        lazy.plugins."lazy.nvim".package = pkgs.vimPlugins.lazy-nvim;
      };

    provides.snacks =
      { mine }:
      {
        vim.utility.snacks-nvim = {
          enable = true;
          setupOpts = {
            dashboard.enabled = true;
            dashboard.preset = lib.optionalAttrs mine {
              header = builtins.readFile ./header.txt;
            };
            explorer.enabled = true;
            input.enabled = true;
            notifier.enabled = true;
            picker.enabled = true;
            quickfile.enabled = true;
            scope.enabed = true;
            scroll.enabled = true;
            statuscolumn.enabled = true;
            words.enabled = true;
          };
        };
      };
  };

}
