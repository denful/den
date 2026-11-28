# Users and policy-driven access mappings.
#
# Users live in den's registry (`den.users`), with extra schema fields and a
# `groups` fact; the user-access assignment policy (policies/fleet.nix) puts
# them on hosts from fleet.user-access grants.
{
  lib,
  config,
  den,
  ...
}:
let
  # Submodule for group-based access grants.
  accessGrantType = lib.types.submodule {
    options.groups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Groups granted access";
    };
  };

  # Group memberships are a fact: assignment reads them before resolution.
  userFacts = {
    options.groups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Group memberships for access policy selection";
    };
  };

  # Extend user schema with registry fields.
  extendUserSchema =
    { ... }:
    {
      options.email = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "User email address";
      };
      options.ssh-keys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "SSH public keys for authorized_keys";
      };
    };

in
{
  # Access mappings: under fleet.
  options.fleet.user-access = {
    by-environment = lib.mkOption {
      type = lib.types.attrsOf accessGrantType;
      default = { };
      description = "Grant user groups access to all hosts in an environment";
    };
    by-host = lib.mkOption {
      type = lib.types.attrsOf accessGrantType;
      default = { };
      description = "Grant user groups access to a specific host";
    };
  };

  config = {
    # Extend user schema with registry fields.
    den.schema.user.imports = [ extendUserSchema ];
    den.schema.user.facts = [ userFacts ];

    # Demo users.
    den.users = {
      alice = {
        email = "alice@example.com";
        facts.groups = [ "admin" ];
        ssh-keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyAlice alice@workstation" ];
      };
      bob = {
        email = "bob@example.com";
        facts.groups = [ "deploy" ];
        ssh-keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyBob bob@laptop" ];
      };
    };

    # Expose registry as flake output for nix eval.
    flake.den.users = config.den.users;

    # Access mappings.
    fleet.user-access = {
      by-environment = {
        staging = {
          groups = [
            "admin"
            "deploy"
          ];
        };
        prod = {
          groups = [ "admin" ];
        };
      };
      by-host = { };
    };
  };
}
