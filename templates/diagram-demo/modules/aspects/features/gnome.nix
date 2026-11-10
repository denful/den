{ ... }:
{
  den.aspects.gnome = {
    # Included by a user: the system part goes to each of the user's hosts.
    provides.to-hosts.nixos.services.xserver.desktopManager.gnome.enable = true;
    homeManager.dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
  };
}
