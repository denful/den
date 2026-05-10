let
  description = ''
    Enables automatic tty login given a username.

    This battery must be included in a Host aspect.

       den.aspects.my-laptop.includes = [ (den.batteries.tty-autologin "root") ];
  '';

  # From https://discourse.nixos.org/t/autologin-for-single-tty/49427/2
  tty-autologin-module =
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
    name = "tty-autologin(${username})";
    meta.provider = [
      "den"
      "provides"
    ];
    nixos = tty-autologin-module username;
  };
in
{
  den.batteries.tty-autologin = {
    inherit description __functor;
  };
}
