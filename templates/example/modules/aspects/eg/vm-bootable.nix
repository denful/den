let
  installer = variant: {
    nixos =
      { modulesPath, ... }:
      {
        imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-${variant}.nix") ];
      };
  };
in
{
  # make USB/VM installers.
  eg.vm-bootable = {
    tui = installer "minimal";
    gui = installer "graphical-base";
  };
}
