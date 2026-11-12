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
  den.batteries.user-shell =
    shell:
    let
      # Built once per call, so every scope the include below reaches gets the
      # same policy record. From den.default it is registered at the host scope
      # and again at the user scope; a second record that is not `==` to the
      # first gets its own identity and delivers the shell again (claim.nix).
      shared = userShell shell;
    in
    {
      inherit description;
      # A stable origin per call (#694 §12): excluding `den.batteries.user-shell`
      # matches every shell.
      name = "user-shell(${shell})";
      meta.aspect-chain = [
        "den"
        "batteries"
      ];

      includes = [
        ({ host, user }: { name = "user-shell/${user.userName}@${host.name}"; } // shared)
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
