{ ... }:
{
  den.aspects.gnome = {
    nixos.services.xserver.desktopManager.gnome.enable = true;
    homeManager.dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
  };
}
