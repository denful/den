# The worked example in docs/src/content/docs/guides/acl-environments.mdx:
# its three files as written there, and the result table it states.
{ denTest, lib, ... }:
let
  # modules/acl-schema.nix
  aclSchema =
    { lib, den, ... }:
    let
      inherit (lib) mkOption types;
      groupNames = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };

      environmentType = den.lib.schema.mkInstanceType {
        strict = den.schema.environment.isStrict;
        extraModules = [
          (
            { config, ... }:
            {
              config._module.args.environment = config;
              options = {
                domain = mkOption { type = types.str; };
                timezone = mkOption {
                  type = types.str;
                  default = "UTC";
                };
                system-access-groups = groupNames;
              };
            }
          )
        ];
      } den.schema.environment;

      groupType = types.submodule {
        options = {
          description = mkOption {
            type = types.str;
            default = "";
          };
          labels = groupNames;
          members = groupNames;
        };
      };
    in
    {
      options.acl = {
        environments = mkOption {
          type = types.attrsOf environmentType;
          default = { };
        };
        groups = mkOption {
          type = types.attrsOf groupType;
          default = { };
        };
      };

      config = {
        den.schema.environment.isEntity = true;
        den.schema.user.classes = lib.mkDefault [ "homeManager" ];

        # What user assignment reads, before any host is resolved.
        den.schema.host.facts = [
          {
            options.environment = mkOption { type = types.str; };
            options.system-access-groups = groupNames;
          }
        ];
        den.schema.user.facts = [ { options.groups = groupNames; } ];

        # The host's environment as an ordinary field too, for the walk below.
        den.schema.host.imports = [
          (
            { config, ... }:
            {
              options.environment = mkOption {
                type = types.str;
                default = config.facts.environment;
              };
            }
          )
        ];
      };
    };

  # modules/acl-policies.nix
  aclPolicies =
    {
      lib,
      den,
      config,
      ...
    }:
    let
      inherit (den.lib.policy) resolve instantiate;
      inherit (config.acl) environments groups;

      # A member of group G is also a member of every group listing G in `members`.
      closure =
        direct:
        map (g: g.key) (
          builtins.genericClosure {
            startSet = map (key: { inherit key; }) direct;
            operator =
              { key }:
              lib.mapAttrsToList (name: _: { key = name; }) (
                lib.filterAttrs (_: g: lib.elem key g.members) groups
              );
          }
        );

      gatesFor =
        host:
        environments.${host.facts.environment}.system-access-groups ++ host.facts.system-access-groups;

      canLogin = host: user: lib.any (g: lib.elem g (gatesFor host)) (closure user.facts.groups);

      posixGroups = user: lib.filter (g: lib.elem "posix" groups.${g}.labels) (closure user.facts.groups);

      allHosts = lib.concatMap lib.attrValues (lib.attrValues den.hosts);

      # Every user is on `host.users` before resolution, so the host sets each
      # one's POSIX groups itself; nothing crosses from user scope.
      posixGroupsOnHost =
        { host }:
        let
          posix = lib.mapAttrs' (_: u: lib.nameValuePair u.userName (posixGroups u)) host.users;
        in
        {
          name = "acl-posix-groups/${host.name}";
          nixos = {
            users.users = builtins.mapAttrs (_: extraGroups: { inherit extraGroups; }) posix;
            users.groups = lib.genAttrs (lib.unique (lib.concatLists (builtins.attrValues posix))) (_: { });
          };
        };

    in
    {
      # flake -> environment
      den.policies.to-environments =
        _:
        lib.mapAttrsToList (_: environment: resolve.to "environment" { inherit environment; }) environments;

      # environment -> host
      den.policies.environment-to-hosts =
        { environment, ... }:
        lib.concatMap (
          host:
          lib.optionals (host.environment == environment.name && host.intoAttr != [ ]) [
            (resolve.to "host" { inherit host; })
            (instantiate host)
          ]
        ) allHosts;

      # Which users each host gets, decided before any host is resolved: every
      # registry user the host's gates admit.
      den.policies.acl-users = den.lib.policy.assign (
        { host, users }: builtins.attrNames (lib.filterAttrs (_: canLogin host) users)
      );

      den.schema.flake.includes = [ den.policies.to-environments ];
      den.schema.environment.includes = [ den.policies.environment-to-hosts ];
      den.schema.host.includes = [
        den.policies.acl-users
        posixGroupsOnHost
      ];

      # The environment walk replaces den's default host walk.
      den.schema.flake-system.excludes = [
        den.policies.system-to-os-outputs
      ];

    };

  # modules/fleet.nix
  fleet =
    { den, ... }:
    {
      acl.environments = {
        prod = {
          domain = "example.com";
          system-access-groups = [ "admins" ];
        };
        dev = {
          domain = "dev.example.com";
          timezone = "Europe/Berlin";
          system-access-groups = [ "developers" ];
        };
      };

      acl.groups = {
        admins.description = "Log in anywhere";
        developers = {
          labels = [ "posix" ];
          members = [ "admins" ]; # every admin is a developer
        };
        wheel = {
          labels = [ "posix" ];
          members = [ "admins" ];
        };
        docker = {
          labels = [ "posix" ];
          members = [ "developers" ];
        };
        grafana-viewers.members = [ "developers" ];
      };

      den.users = {
        tux.facts.groups = [ "admins" ];
        alice.facts.groups = [ "developers" ];
        bob.facts.groups = [ "grafana-viewers" ];
      };

      den.hosts.x86_64-linux = {
        igloo.facts.environment = "prod";
        iceberg.facts = {
          environment = "dev";
          system-access-groups = [ "grafana-viewers" ]; # host-only gate
        };
      };

      den.aspects.environment-defaults.nixos =
        { environment, ... }:
        {
          networking.domain = environment.domain;
          time.timeZone = environment.timezone;
        };

      den.default.includes = [
        den.batteries.define-user
        den.batteries.hostname
        den.aspects.environment-defaults
      ];
    };

  guide = {
    imports = [
      aclSchema
      aclPolicies
      fleet
    ];
  };

  sorted = lib.sort (a: b: a < b);
  accounts = os: sorted (builtins.attrNames (lib.filterAttrs (_: u: u.isNormalUser) os.users.users));
  extraGroupsOf = os: n: sorted os.users.users.${n}.extraGroups;
in
{
  flake.tests.acl-environments = {

    test-who-logs-in-where = denTest (
      { igloo, iceberg, ... }:
      {
        imports = [ guide ];
        expr = {
          igloo = accounts igloo;
          iceberg = accounts iceberg;
        };
        expected = {
          igloo = [ "tux" ];
          iceberg = [
            "alice"
            "bob"
            "tux"
          ];
        };
      }
    );

    test-posix-groups = denTest (
      { igloo, iceberg, ... }:
      {
        imports = [ guide ];
        expr = {
          igloo.tux = extraGroupsOf igloo "tux";
          iceberg = {
            alice = extraGroupsOf iceberg "alice";
            bob = extraGroupsOf iceberg "bob";
            tux = extraGroupsOf iceberg "tux";
          };
        };
        expected = {
          igloo.tux = [
            "developers"
            "docker"
            "wheel"
          ];
          iceberg = {
            alice = [
              "developers"
              "docker"
            ];
            bob = [ ];
            tux = [
              "developers"
              "docker"
              "wheel"
            ];
          };
        };
      }
    );

    test-environment-settings = denTest (
      { igloo, iceberg, ... }:
      {
        imports = [ guide ];
        expr = {
          igloo = {
            inherit (igloo.networking) domain;
            inherit (igloo.time) timeZone;
          };
          iceberg = {
            inherit (iceberg.networking) domain;
            inherit (iceberg.time) timeZone;
          };
        };
        expected = {
          igloo = {
            domain = "example.com";
            timeZone = "UTC";
          };
          iceberg = {
            domain = "dev.example.com";
            timeZone = "Europe/Berlin";
          };
        };
      }
    );

    # "Tell host aspects who is admitted": a host aspect reads `host.users`.
    test-host-aspect-reads-admitted-users = denTest (
      {
        den,
        iceberg,
        igloo,
        ...
      }:
      {
        imports = [ guide ];
        den.aspects.wireshark =
          { host }:
          {
            nixos = {
              programs.wireshark.enable = true;
              users.users = lib.mapAttrs' (
                _: user: lib.nameValuePair user.userName { extraGroups = [ "wireshark" ]; }
              ) host.users;
            };
          };
        den.aspects.iceberg.includes = [ den.aspects.wireshark ];
        expr = {
          iceberg = builtins.filter (n: builtins.elem "wireshark" iceberg.users.users.${n}.extraGroups) (
            accounts iceberg
          );
          igloo = builtins.filter (n: builtins.elem "wireshark" igloo.users.users.${n}.extraGroups) (
            accounts igloo
          );
        };
        expected = {
          iceberg = [
            "alice"
            "bob"
            "tux"
          ];
          igloo = [ ];
        };
      }
    );

    # The guide's users are assigned before resolution, so den's own readers
    # of `host.users` see them, with no resolution-stage warning.
    test-no-migration-warning = denTest (
      { den, iceberg, ... }:
      {
        imports = [ guide ];
        den.internal.warningsAsErrors = true;
        expr = builtins.attrNames den.hosts.x86_64-linux.iceberg.users;
        expected = [
          "alice"
          "bob"
          "tux"
        ];
      }
    );

  };
}
