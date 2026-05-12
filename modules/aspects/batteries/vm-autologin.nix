let
  description = ''
    Enables automatic tty login given a username when running `nixos-rebuild build-vm`.

    This battery must be included in a Host aspect.

       den.aspects.my-laptop.includes = [ (den.batteries.vm-autologin "root") ];
  '';

  # From https://discourse.nixos.org/t/autologin-for-single-tty/49427/2
  vm-autologin-module =
    username:
    { pkgs, config, ... }:
    {
      systemd.services."getty@tty1" = {
        overrideStrategy = "asDropin";
        serviceConfig.ExecStart = [
          ""
          "@${pkgs.util-linux}/sbin/agetty agetty --login-program ${config.services.getty.loginProgram} --autologin ${username} --noclear --keep-baud %I 115200,38400,9600 $TERM"
        ];
      };
    };

  __functor = _self: username: {
    name = "vm-autologin(${username})";
    meta.provider = [
      "den"
      "provides"
    ];
    nixos.virtualisation.vmVariant = vm-autologin-module username;
  };
in
{
  den.batteries.vm-autologin = {
    inherit description __functor;
  };
}
