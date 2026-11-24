# The ACL environments guide and the fleet-demo template move group grants
# from resolution-stage `resolve.to "user"` policies to one assignment
# policy over facts (#781). Both arms below run on the same fleet and must
# give every host the same accounts, negative grants included.
{ denTest, lib, ... }:
let
  # fleet-demo's hosts and users, plus a host no grant matches, an
  # identity-only user no grant reaches, and one per-host grant.
  environments = {
    lb-prod = "prod";
    web-prod-1 = "prod";
    web-prod-2 = "prod";
    web-staging = "staging";
    lab = "dev";
  };
  userGroups = {
    alice = [ "admin" ];
    bob = [ "deploy" ];
    carol = [ "sso" ];
  };
  access = {
    by-environment = {
      staging.groups = [
        "admin"
        "deploy"
      ];
      prod.groups = [ "admin" ];
    };
    by-host.web-prod-2.groups = [ "deploy" ];
  };
  granted =
    host: environment:
    (access.by-environment.${environment} or { groups = [ ]; }).groups
    ++ (access.by-host.${host} or { groups = [ ]; }).groups;
  inGroups = groups: g: builtins.any (x: builtins.elem x groups) g;

  common =
    { den, ... }:
    {
      den.default.includes = [ den.provides.define-user ];
      den.schema.user.classes = lib.mkForce [ "user" ];
    };

  # Before: `environment` and `groups` are plain fields, and two host policies
  # resolve registry users during resolution, with host-to-users excluded.
  legacy =
    { den, ... }:
    {
      imports = [ common ];
      den.migrations.resolution-assignments.suppressWarnings = true;
      den.schema.host.imports = [
        { options.environment = lib.mkOption { type = lib.types.str; }; }
      ];
      den.schema.user.imports = [
        {
          options.groups = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        }
      ];
      den.users = builtins.mapAttrs (_: groups: { inherit groups; }) userGroups;
      den.hosts.x86_64-linux = builtins.mapAttrs (_: environment: { inherit environment; }) environments;
      den.policies.acl-grants =
        { host, ... }:
        map (n: den.lib.policy.resolve.to "user" { user = den.users.${n}; }) (
          builtins.filter (n: inGroups (granted host.name host.environment) den.users.${n}.groups) (
            builtins.attrNames den.users
          )
        );
      den.schema.host.includes = [ den.policies.acl-grants ];
      den.schema.host.excludes = [ den.policies.host-to-users ];
    };

  # After: both are facts, and one assignment policy reads them.
  migrated =
    { den, ... }:
    {
      imports = [ common ];
      den.schema.host.facts = [
        { options.environment = lib.mkOption { type = lib.types.str; }; }
      ];
      den.schema.user.facts = [
        {
          options.groups = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        }
      ];
      den.users = builtins.mapAttrs (_: groups: { facts.groups = groups; }) userGroups;
      den.hosts.x86_64-linux = builtins.mapAttrs (_: environment: {
        facts.environment = environment;
      }) environments;
      den.policies.acl-grants = den.lib.policy.assign (
        { host, users }:
        builtins.attrNames (
          lib.filterAttrs (_: u: inGroups (granted host.name host.facts.environment) u.facts.groups) users
        )
      );
      den.schema.host.includes = [ den.policies.acl-grants ];
    };

  accounts =
    config:
    builtins.mapAttrs (
      h: _:
      builtins.attrNames (
        lib.filterAttrs (_: u: u.isNormalUser) config.flake.nixosConfigurations.${h}.config.users.users
      )
    ) environments;

  expected = {
    lb-prod = [ "alice" ];
    web-prod-1 = [ "alice" ];
    web-prod-2 = [
      "alice"
      "bob"
    ];
    web-staging = [
      "alice"
      "bob"
    ];
    lab = [ ];
  };
in
{
  flake.tests.acl-assignment-migration = {

    test-legacy-resolution-policies = denTest (
      { config, ... }:
      {
        imports = [ legacy ];
        expr = accounts config;
        inherit expected;
      }
    );

    test-assignment-policy-over-facts = denTest (
      { config, ... }:
      {
        imports = [ migrated ];
        expr = accounts config;
        inherit expected;
      }
    );

    # The identity-only user stays in the registry, on no host.
    test-identity-only-user-stays-registered = denTest (
      { den, ... }:
      {
        imports = [ migrated ];
        expr = {
          registered = den.users ? carol;
          onAnyHost = builtins.any (h: h.users ? carol) (builtins.attrValues den.hosts.x86_64-linux);
        };
        expected = {
          registered = true;
          onAnyHost = false;
        };
      }
    );

  };
}
