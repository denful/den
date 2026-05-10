{ den, inputs, ... }:
{
  # we can import this flakeModule even if we dont have flake-parts as input!
  imports = [ inputs.den.flakeModule ];

  den.default.nixos = {
    # remove for real host
    fileSystems."/".device = "/dev/fake";
    fileSystems."/".fsType = "auto";
    boot.loader.grub.enable = false;
  };

  # tux user on igloo host, using nix-maid
  den.hosts.x86_64-linux.igloo.users = {
    tux.classes = [ "maid" ];
    pingu.classes = [ "hjem" ];
  };

  # first: `npins add -n darwin github nix-darwin nix-darwin`
  # den.hosts.aarch64-darwin.apple.users.tux.classes = [ "hjem" ];

  # host aspect
  den.aspects.igloo = {
    nixos =
      { pkgs, ... }:
      {
        environment.systemPackages = [
          pkgs.vim
        ];
      };
  };

  # include den batteries or your own re-usable aspects
  # this affects all users, could also be done per user
  den.schema.user.includes = [ den.batteries.define-user ];

  # user aspect
  den.aspects.tux = {
    # user configures host <nixos/darwin>.users.users.tux.description
    # Read docs about the `user` class.
    user.description = "Cute Penguin";

    # user contributes nixos and darwin common config
    os =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.hello ];
      };

    # maid class
    maid.file.home.".gitconfig".text = ''
      [user]
        name=Tux
    '';
  };

  den.aspects.pingu = {
    hjem.files.".foo".text = "bar";
  };
}
