# User registry and policy-driven access mappings.
#
# Demonstrates a standalone user registry with extended schema,
# resolved onto hosts via fleet.user-access group policies.
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

  # Extend user schema with registry fields.
  extendUserSchema =
    { ... }:
    {
      options.email = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "User email address";
      };
      options.groups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Group memberships for access policy selection";
      };
      options.ssh-keys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "SSH public keys for authorized_keys";
      };
    };

  # Registry entry type — mirrors the standard user entity shape from
  # nix/lib/entities/host.nix so that pipeline self-provide, define-user,
  # and other batteries find the expected attributes (userName, aspect, classes).
  registryUserType = den.lib.schema.mkInstanceType {
    strict = false;
    extraModules = [
      (
        { name, config, ... }:
        {
          config._module.args.user = config;
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "User name (from attrset key)";
            };
            userName = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "User account name";
            };
            classes = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "user" ];
              description = "Home management nix classes";
            };
            aspect = lib.mkOption {
              type = lib.types.raw;
              default = if den.aspects ? ${name} then den.aspects.${name} else { };
              defaultText = "den.aspects.<name>";
              description = "Aspect that configures this user";
            };
          };
        }
      )
    ];
  } den.schema.user;
in
{
  # Registry: standalone, not under fleet.
  options.den.users.registry = lib.mkOption {
    type = lib.types.attrsOf registryUserType;
    default = { };
    description = "External user registry with extended schema";
  };

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
    # Promote users to real entities.
    den.schema.user.isEntity = true;

    # Extend user schema with registry fields.
    den.schema.user.imports = [ extendUserSchema ];

    # Demo users.
    den.users.registry = {
      alice = {
        email = "alice@example.com";
        groups = [ "admin" ];
        ssh-keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyAlice alice@workstation" ];
      };
      bob = {
        email = "bob@example.com";
        groups = [ "deploy" ];
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
