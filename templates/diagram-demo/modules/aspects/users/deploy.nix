{ lib, ... }:
{
  den.aspects.deploy = {
    nixos =
      { ... }:
      {
        users.users.deploy = {
          isNormalUser = lib.mkForce false;
          isSystemUser = true;
          group = "deploy";
        };
        users.groups.deploy = { };
      };
  };
}
