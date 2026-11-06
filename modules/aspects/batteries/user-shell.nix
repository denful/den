{ den, lib, ... }:
let

  description = ''
    Sets a user default shell, enables the shell at OS and Home level.

    Usage:

      den.aspects.vic.includes = [
        # will always love red snappers.
        (den.batteries.user-shell "fish")
      ];
  '';

  # Delivered to the host from each user scope, wherever the battery is
  # included (a host-side include fans out to the users).
  hostShell =
    shell:
    {
      host,
      user,
      home ? null,
      ...
    }:
    # A standalone home binds a host that is not its ancestor: no receiver.
    # Only an OS host has these settings, as on main.
    lib.optional
      (
        host ? class
        && home == null
        && builtins.elem host.class [
          "nixos"
          "darwin"
        ]
      )
      (
        den.lib.policy.provide {
          class = host.class;
          module =
            { pkgs, ... }:
            {
              programs.${shell}.enable = true;
              users.users.${user.userName}.shell = pkgs.${shell};
            }
            // lib.optionalAttrs (host.class == "darwin") { environment.shells = [ pkgs.${shell} ]; };
          receiver = host;
        }
      );

  userShell = shell: {
    includes = [
      {
        __isPolicy = true;
        name = "user-shell-host/${shell}";
        fn = hostShell shell;
      }
    ];
    homeManager = {
      programs.${shell}.enable = true;
    };
  };

in
{
  den.batteries.user-shell = shell: {
    inherit description;

    includes = [
      ({ host, user }: { name = "user-shell/${user.userName}@${host.name}"; } // userShell shell)
      (
        { home }:
        {
          name = "user-shell/${home.name}";
          homeManager.programs.${shell}.enable = true;
        }
      )
    ];
  };
}
