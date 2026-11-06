{ den, lib, ... }:
let
  description = ''
    Sets user as *primary*.

    On NixOS adds wheel and networkmanager groups.
    On Darwin sets user as system.primaryUser
    On WSL sets defaultUser if host has `wsl` support.

    ## Usage

       den.aspects.my-user.includes = [ den.batteries.primary-user ];

  '';

  # Delivered to the host from each user scope, wherever the battery is
  # included (a host-side include fans out to the users).
  hostSettings =
    {
      user,
      host,
      home ? null,
      ...
    }:
    # A standalone home binds a host that is not its ancestor: no receiver.
    # Only an OS host has these settings, as on main.
    lib.optionals
      (
        host ? class
        && home == null
        && builtins.elem host.class [
          "nixos"
          "darwin"
        ]
      )
      (
        lib.optional (host.class == "nixos") (
          den.lib.policy.provide {
            class = "nixos";
            path = [
              "users"
              "users"
              user.userName
            ];
            module = {
              isNormalUser = true;
              extraGroups = [
                "wheel"
                "networkmanager"
              ];
            };
            receiver = host;
          }
        )
        ++ lib.optional (host.class == "darwin") (
          den.lib.policy.provide {
            class = "darwin";
            module.system.primaryUser = user.userName;
            receiver = host;
          }
        )
        ++ [
          (den.lib.policy.provide {
            class = "wsl";
            path = [ "defaultUser" ];
            module = user.userName;
            receiver = host;
          })
        ]
      );

  userToHostContext =
    { user, host, ... }:
    {
      name = "primary-user(${user.userName}@${host.name})";
      inherit description;
      includes = [
        {
          __isPolicy = true;
          name = "primary-user-host-settings";
          fn = hostSettings;
        }
      ];
    };

in
{
  den.batteries.primary-user = userToHostContext;
}
