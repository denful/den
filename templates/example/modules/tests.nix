# Some CI checks to ensure this template always works.
# Feel free to adapt or remove when this repo is yours.
{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      self',
      lib,
      ...
    }:
    let
      checkCond = name: cond: pkgs.runCommandLocal name { } (if cond then "touch $out" else "");
      apple = inputs.self.darwinConfigurations.apple.config;
      igloo = inputs.self.nixosConfigurations.igloo.config;
      alice-at-igloo = igloo.home-manager.users.alice;
      vmBuilds = !pkgs.stdenvNoCC.isLinux || builtins.pathExists (self'.packages.vm + "/bin/vm");
      iglooBuilds = !pkgs.stdenvNoCC.isLinux || builtins.pathExists (igloo.system.build.toplevel);
      appleBuilds = !pkgs.stdenvNoCC.isDarwin || builtins.pathExists (apple.system.build.toplevel);
    in
    {
      # checks."igloo builds" = checkCond "igloo-builds" iglooBuilds;
      # checks."apple builds" = checkCond "apple-builds" appleBuilds;
      # checks."vm builds" = checkCond "vm-builds" vmBuilds;

      checks."alice enabled igloo nh" = checkCond "alice.igloo" igloo.programs.nh.enable;
      checks."igloo enabled alice tmux" = checkCond "igloo.alice" alice-at-igloo.programs.tmux.enable;

      checks."alice-custom-emacs" = checkCond "hm.programs.emacs.package" (
        "emacs-nox" == lib.getName alice-at-igloo.programs.emacs.package
      );
    };
}
