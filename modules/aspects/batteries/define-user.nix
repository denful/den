{ den, lib, ... }:
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

  # Delivered to the host from each user scope, wherever the battery is
  # included (a host-side include fans out to the users).
  account =
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
          path = [
            "users"
            "users"
            user.userName
          ];
          module = {
            name = user.userName;
            home = homeDir host user;
          }
          // lib.optionalAttrs (host.class == "nixos") { isNormalUser = true; };
          receiver = host;
        }
      );

  userContext =
    { host, user }:
    {
      name = "define-user/${user.userName}@${host.name}";
      includes = [
        {
          __isPolicy = true;
          name = "define-user-account";
          fn = account;
        }
      ];
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
