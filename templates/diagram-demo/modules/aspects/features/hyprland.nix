{ den, ... }:
{
  den.aspects.hyprland = {
    includes = [
      (den.batteries.unfree [
        "nvidia-x11"
        "nvidia-settings"
      ])
    ];
    # Included by a user: the system part goes to each of the user's hosts.
    provides.to-hosts.nixos.programs.hyprland.enable = true;
    homeManager.wayland.windowManager.hyprland.enable = true;
  };
}
