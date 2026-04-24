# Core entity policies — fundamental traversal between entity kinds.
#
# Policy resolve functions can safely destructure context args because
# synthesize-policies.nix validates entity keys before calling resolve.
{ lib, ... }:
{
  den.policies = {
    host-to-users = {
      _core = true;
      from = "host";
      to = "user";
      resolve =
        { host, ... }:
        map (user: {
          inherit host user;
        }) (lib.attrValues host.users);
    };
    host-to-default = {
      _core = true;
      from = "host";
      to = "default";
      resolve = lib.singleton;
    };
    user-to-default = {
      _core = true;
      from = "user";
      to = "default";
      resolve = lib.singleton;
    };
    home-to-default = {
      _core = true;
      from = "home";
      to = "default";
      resolve = lib.singleton;
    };
  };
}
