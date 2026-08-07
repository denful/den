{ ... }:
let

  description = ''
    Sets a user default shell, enables the shell at OS and Home level.

    Usage:

      den.aspects.vic.includes = [
        # will always love red snappers.
        (den.batteries.user-shell "fish")
      ];
  '';

  userShell = shell: user: {
    nixos =
      { pkgs, ... }:
      {
        programs.${shell}.enable = true;
        users.users.${user.userName}.shell = pkgs.${shell};
      };

    darwin =
      { pkgs, ... }:
      {
        programs.${shell}.enable = true;
        users.users.${user.userName}.shell = pkgs.${shell};
        environment.shells = [ pkgs.${shell} ];
      };

    homeManager = {
      programs.${shell}.enable = true;
    };
  };

in
{
  den.batteries.user-shell = shell: {
    inherit description;

    includes = [
      ({ host, user }: { name = "user-shell/${user.userName}@${host.name}"; } // userShell shell user)
      ({ home }: { name = "user-shell/${home.name}"; } // userShell shell home)
    ];
  };
}
