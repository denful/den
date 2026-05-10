{ den, ... }:
{
  den.default = {
    nixos.system.stateVersion = "25.11";
    homeManager.home.stateVersion = "25.11";
    includes = [
      den.batteries.hostname
      den.batteries.define-user
    ];
    # Stub boot config so NixOS evaluation doesn't fail
    nixos.boot.loader.grub.enable = false;
    nixos.fileSystems."/".device = "/dev/null";
    nixos.fileSystems."/".fsType = "tmpfs";
  };
}
