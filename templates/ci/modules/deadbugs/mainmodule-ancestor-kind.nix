# A host's mainModule against its configuration, under an entity kind above hosts.
{ denTest, lib, ... }:
let
  marks =
    etc: builtins.sort (a: b: a < b) (builtins.filter (lib.hasPrefix "mark-") (builtins.attrNames etc));

  base = {
    boot.loader.grub.enable = false;
    fileSystems."/" = {
      device = "/dev/null";
      fsType = "auto";
    };
  };

  # flake-system -> environment prod -> every host, as a fleet topology declares.
  envTopology =
    { den, ... }:
    let
      inherit (den.lib.policy) resolve instantiate;
    in
    {
      den.schema.environment.isEntity = true;
      den.schema.host.parent = "environment";
      den.schema.flake-system.excludes = [ den.policies.system-to-os-outputs ];
      den.policies.test-env-walk =
        { system, ... }:
        [
          (resolve.to "environment" {
            environment = {
              name = "prod";
              aspect = den.aspects.prod-env;
            };
          })
        ];
      den.policies.test-env-to-host =
        { environment, ... }:
        lib.concatMap (
          host:
          lib.optionals (host.intoAttr != [ ]) [
            (resolve.to "host" { inherit host; })
            (instantiate host)
          ]
        ) (builtins.attrValues (den.hosts.x86_64-linux or { }));
      den.schema.flake-system.includes = [ den.policies.test-env-walk ];
      den.schema.environment.includes = [ den.policies.test-env-to-host ];
      den.aspects.prod-env.nixos = { };
    };

  common =
    { den, ... }:
    {
      den.default.homeManager.home.stateVersion = "25.11";
      den.default.includes = [ den._.define-user ];
      den.schema.user.classes = [ "homeManager" ];
      den.default.nixos = base // {
        environment.etc."mark-base".text = "b";
      };
      den.hosts.x86_64-linux.igloo.users.tux = { };
    };

  fromMain =
    h:
    (h.instantiate {
      modules = [
        h.mainModule
        { nixpkgs.hostPlatform = h.system; }
      ];
    }).config;

  # mainModule's markers against the flake's configuration's.
  cell =
    extra:
    denTest (
      { den, igloo, ... }:
      {
        imports = [
          common
          envTopology
          extra
        ];
        expr = marks (fromMain den.hosts.x86_64-linux.igloo).environment.etc;
        expected = marks igloo.environment.etc;
      }
    );
in
{
  flake.tests.mainmodule-ancestor-kind = {

    # A host include that needs the environment's context.
    test-environment-context-include = cell (
      { den, ... }:
      {
        den.aspects.envx.nixos.environment.etc."mark-env".text = "e";
        den.schema.host.includes = [
          (
            { environment, host, ... }:
            {
              includes = [ den.aspects.envx ];
            }
          )
        ];
      }
    );

    # The environment's provides.to-users, with host-class content.
    test-environment-provides-to-users = cell (
      { den, ... }:
      {
        den.aspects.prod-env.provides.to-users.includes = [
          { nixos.environment.etc."mark-to-users".text = "u"; }
        ];
      }
    );

    # The environment kind excludes content the host includes.
    test-environment-exclude = cell (
      { den, ... }:
      {
        den.aspects.dropped.nixos.environment.etc."mark-dropped".text = "d";
        den.aspects.kept.nixos.environment.etc."mark-kept".text = "k";
        den.aspects.igloo.includes = [
          den.aspects.dropped
          den.aspects.kept
        ];
        den.schema.environment.excludes = [ den.aspects.dropped ];
      }
    );

    # The environment's provides.to-users, with home-manager content.
    test-environment-provides-to-users-home-manager = denTest (
      { den, igloo, ... }:
      {
        imports = [
          common
          envTopology
        ];
        den.aspects.prod-env.provides.to-users.includes = [
          { homeManager.home.file."mark-hm".text = "h"; }
        ];
        expr = marks (fromMain den.hosts.x86_64-linux.igloo).home-manager.users.tux.home.file;
        expected = marks igloo.home-manager.users.tux.home.file;
      }
    );

    # A value collected from a sibling host through a pipe.
    test-sibling-pipe-collect = denTest (
      { den, igloo, ... }:
      let
        h = den.hosts.x86_64-linux.igloo;
      in
      {
        imports = [
          common
          envTopology
        ];
        den.hosts.x86_64-linux.iceberg = { };
        den.quirks.addrs.description = "addresses";
        den.policies.collect-addrs =
          { host, ... }:
          [ (den.lib.policy.pipe.from "addrs" [ (den.lib.policy.pipe.collect ({ host, ... }: true)) ]) ];
        den.schema.host.includes = [ den.policies.collect-addrs ];
        den.aspects.iceberg.addrs = "10.0.0.2";
        den.aspects.igloo = {
          addrs = "10.0.0.1";
          nixos =
            { addrs, lib, ... }:
            {
              networking.domain = lib.concatStringsSep "," (lib.sort (a: b: a < b) addrs);
            };
        };
        expr = (fromMain h).networking.domain;
        expected = igloo.networking.domain;
      }
    );

    # Two hosts with the same name on two systems: each mainModule is its own.
    test-same-name-two-systems = denTest (
      { den, config, ... }:
      let
        inherit (den.lib.policy) resolve instantiate;
        cfgOf = n: config.flake.nixosConfigurations.${n}.config;
      in
      {
        imports = [ common ];
        den.schema.environment.isEntity = true;
        den.schema.host.parent = "environment";
        den.schema.flake-system.excludes = [ den.policies.system-to-os-outputs ];
        den.policies.test-env-walk =
          { system, ... }: [ (resolve.to "environment" { environment.name = "prod-${system}"; }) ];
        den.policies.test-env-to-host =
          { environment, system, ... }:
          lib.concatMap (host: [
            (resolve.to "host" { inherit host; })
            (instantiate host)
          ]) (builtins.attrValues (den.hosts.${system} or { }));
        den.schema.flake-system.includes = [ den.policies.test-env-walk ];
        den.schema.environment.includes = [ den.policies.test-env-to-host ];
        den.hosts.aarch64-linux.igloo.intoAttr = [
          "nixosConfigurations"
          "igloo-arm"
        ];
        den.schema.host.includes = [
          (
            { environment, host, ... }:
            {
              nixos.environment.etc."mark-${host.system}".text = environment.name;
            }
          )
        ];
        expr = map (n: marks (fromMain n.h).environment.etc) [
          { h = den.hosts.x86_64-linux.igloo; }
          { h = den.hosts.aarch64-linux.igloo; }
        ];
        expected = [
          (marks (cfgOf "igloo").environment.etc)
          (marks (cfgOf "igloo-arm").environment.etc)
        ];
      }
    );

    # A host the flake doesn't instantiate keeps its host-rooted resolve.
    test-not-instantiated-host = denTest (
      { den, ... }:
      {
        imports = [
          common
          envTopology
        ];
        den.hosts.x86_64-linux.shelf.intoAttr = [ ];
        den.aspects.shelf.nixos.environment.etc."mark-shelf".text = "s";
        expr = marks (fromMain den.hosts.x86_64-linux.shelf).environment.etc;
        expected = [
          "mark-base"
          "mark-shelf"
        ];
      }
    );

    # The same host delivered from two scopes is refused by name.
    test-duplicate-delivery-refused = denTest (
      { den, ... }:
      let
        inherit (den.lib.policy) resolve instantiate;
      in
      {
        imports = [ common ];
        den.schema.environment.isEntity = true;
        den.schema.host.parent = "environment";
        den.schema.flake-system.excludes = [ den.policies.system-to-os-outputs ];
        den.policies.test-env-walk =
          { system, ... }:
          map (n: resolve.to "environment" { environment.name = n; }) [
            "a"
            "b"
          ];
        den.policies.test-env-to-host =
          { environment, ... }:
          [
            (resolve.to "host" { host = den.hosts.x86_64-linux.igloo; })
            (instantiate den.hosts.x86_64-linux.igloo)
          ];
        den.schema.flake-system.includes = [ den.policies.test-env-walk ];
        den.schema.environment.includes = [ den.policies.test-env-to-host ];
        expr = (fromMain den.hosts.x86_64-linux.igloo).environment.etc ? "mark-base";
        expectedError = {
          type = "ThrownError";
          msg = "den: two scopes deliver igloo";
        };
      }
    );

    # No kind above hosts: mainModule stays lazy in its siblings.
    test-no-parent-sibling-include-poison = denTest (
      { den, ... }:
      {
        imports = [ common ];
        den.hosts.x86_64-linux.iceberg = { };
        den.aspects.iceberg.includes = [ (_: throw "den-test: sibling include forced") ];
        expr = marks (fromMain den.hosts.x86_64-linux.igloo).environment.etc;
        expected = [ "mark-base" ];
      }
    );
    test-no-parent-sibling-option-poison = denTest (
      { den, ... }:
      {
        imports = [ common ];
        den.hosts.x86_64-linux.iceberg = { };
        den.aspects.iceberg.nixos.environment.etc."poison".text = throw "den-test: sibling option forced";
        expr = marks (fromMain den.hosts.x86_64-linux.igloo).environment.etc;
        expected = [ "mark-base" ];
      }
    );

    # With one: a sibling's include reaches it, as it reaches the configuration; its options don't.
    test-parent-sibling-option-poison = denTest (
      { den, ... }:
      {
        imports = [
          common
          envTopology
        ];
        den.hosts.x86_64-linux.iceberg = { };
        den.aspects.iceberg.nixos.environment.etc."poison".text = throw "den-test: sibling option forced";
        expr = marks (fromMain den.hosts.x86_64-linux.igloo).environment.etc;
        expected = [ "mark-base" ];
      }
    );
    test-parent-sibling-include-poison = denTest (
      { den, ... }:
      {
        imports = [
          common
          envTopology
        ];
        den.hosts.x86_64-linux.iceberg = { };
        den.aspects.iceberg.includes = [ (_: throw "den-test: sibling include forced") ];
        expr = marks (fromMain den.hosts.x86_64-linux.igloo).environment.etc;
        expectedError = {
          type = "ThrownError";
          msg = "den-test: sibling include forced";
        };
      }
    );

    # Binding a peer's mainModule or asking `? imports` in the walk forces nothing.
    test-in-walk-peer-mainmodule-shape = denTest (
      { den, igloo, ... }:
      {
        imports = [
          common
          envTopology
        ];
        den.hosts.x86_64-linux.iceberg = { };
        den.schema.host.includes = [
          (
            { host, ... }:
            lib.optionalAttrs (host.name == "igloo" && den.hosts.x86_64-linux.iceberg.mainModule ? imports) {
              nixos.environment.etc."mark-peer-shape".text = "y";
            }
          )
        ];
        expr = igloo.environment.etc ? "mark-peer-shape";
        expected = true;
      }
    );

    # Directly, since no fixture reaches an empty delivery.
    test-mainmodule-imports-selection = denTest (
      { den, ... }:
      let
        sel = den.lib.aspects.__mainModuleImports;
      in
      {
        expr = [
          (sel {
            gated = true;
            delivered = [ "fleet" ];
            rooted = [ "rooted" ];
          })
          (sel {
            gated = true;
            delivered = null;
            rooted = [ "rooted" ];
          })
          (sel {
            gated = false;
            delivered = [ "fleet" ];
            rooted = [ "rooted" ];
          })
        ];
        expected = [
          [ "fleet" ]
          [ "rooted" ]
          [ "rooted" ]
        ];
      }
    );
  };
}
