{ lib, den, ... }:
{
  den.default.nixos.system.stateVersion = "25.11";
  den.default.homeManager.home.stateVersion = "25.11";

  # enable hm by default
  den.schema.user.classes = lib.mkDefault [ "homeManager" ];

  # Hosts receive what their users provide them (`provides.to-hosts`, see
  # tux.nix).
  den.schema.host.includes = [ den.batteries.mutual-provider ];

  # User TODO: REMOVE THIS
  den.aspects.igloo.nixos = {
    boot.loader.grub.enable = false;
    fileSystems."/".device = "/dev/fake";
    fileSystems."/".fsType = "auto";
  };
}
