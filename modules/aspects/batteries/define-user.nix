{ lib, ... }:
let
  description = ''
    Defines a user at OS and Home levels.

    Works in NixOS/Darwin and standalone Home-Manager

    ## Usage

       # for NixOS/Darwin
       den.aspects.my-user.includes = [ den.batteries.define-user ]

       # for standalone home-manager
       den.aspects.my-home.includes = [ den.batteries.define-user ]

    or globally (automatically applied depending on context):

       den.default.includes = [ den.batteries.define-user ]
  '';

  homeDir =
    host: user:
    if lib.hasSuffix "darwin" host.system then "/Users/${user.userName}" else "/home/${user.userName}";

  userContext =
    { host, user }:
    {
      name = "define-user/${user.userName}@${host.name}";
      nixos.users.users.${user.userName} = {
        name = user.userName;
        home = homeDir host user;
        isNormalUser = true;
      };
      darwin.users.users.${user.userName} = {
        name = user.userName;
        home = homeDir host user;
      };
      homeManager = {
        home.username = user.userName;
        home.homeDirectory = homeDir host user;
      };
    };

  hmContext =
    { home }:
    userContext {
      host.system = home.system;
      user.userName = home.userName;
    }
    // {
      name = "define-user/home";
    };
in
{
  den.batteries.define-user = {
    name = "define-user";
    inherit description;
    includes = [
      userContext
      hmContext
    ];
  };
}
