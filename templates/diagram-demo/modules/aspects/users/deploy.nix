{ lib, ... }:
{
  den.aspects.deploy = {
    # A system account: host configuration the user provides to its hosts.
    provides.to-hosts.nixos = {
      users.users.deploy = {
        isNormalUser = lib.mkForce false;
        isSystemUser = true;
        group = "deploy";
      };
      users.groups.deploy = { };
    };
  };
}
