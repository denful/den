{ ... }:
let
  description = ''
    Sets user as *primary*.

    On NixOS adds wheel and networkmanager groups.
    On Darwin sets user as system.primaryUser
    On WSL sets defaultUser if host has `wsl` support.

    ## Usage

       den.aspects.my-user.includes = [ den.batteries.primary-user ];

  '';

  userToHostContext =
    { user, host, ... }:
    {
      name = "primary-user(${user.userName}@${host.name})";
      inherit description;
      darwin.system.primaryUser = user.userName;
      wsl.defaultUser = user.userName;
      nixos.users.users.${user.userName} = {
        isNormalUser = true;
        extraGroups = [
          "wheel"
          "networkmanager"
        ];
      };
    };

in
{
  den.batteries.primary-user = userToHostContext;
}
