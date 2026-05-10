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

  userShell =
    shell: user:
    let
      nixos =
        { pkgs, ... }:
        {
          programs.${shell}.enable = true;
          users.users.${user.userName}.shell = pkgs.${shell};
        };
      darwin = nixos;
      homeManager.programs.${shell}.enable = true;
    in
    {
      inherit nixos darwin homeManager;
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
