{ denTest, lib, ... }:
{
  flake.tests.cross-context-forward = {

    test-resolve-other-host-context = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.hosts.x86_64-linux.iceberg = { };

        den.aspects.igloo.nixos.environment.sessionVariables.FROM_IGLOO = "yes";

        expr =
          let
            iglooCtx = den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; };
            resolved = den.lib.aspects.resolve "nixos" iglooCtx;
          in
          resolved ? imports;
        expected = true;
      }
    );

    test-entities-have-resolved = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.homes.x86_64-linux.cabin = { };

        expr = {
          host = den.hosts.x86_64-linux.igloo ? resolved;
          user = den.hosts.x86_64-linux.igloo.users.tux ? resolved;
          home = den.homes.x86_64-linux.cabin ? resolved;
        };
        expected = {
          host = true;
          user = true;
          home = true;
        };
      }
    );

    test-user-resolved-produces-aspect = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux =
          { host, user }:
          {
            nixos.environment.sessionVariables.USER_HOST = "${user.userName}@${host.hostName}";
          };

        expr =
          let
            user = den.hosts.x86_64-linux.igloo.users.tux;
            resolved = den.lib.aspects.resolve "nixos" user.resolved;
          in
          resolved ? imports;
        expected = true;
      }
    );

    test-cross-context-forward-with-ctx = denTest (
      { den, iceberg, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.hosts.x86_64-linux.iceberg = { };

        den.aspects.igloo.ssh-host-key.environment.sessionVariables.FROM_IGLOO = "yes";

        den.aspects.iceberg.includes = [
          (
            { host }:
            den.provides.forward {
              each = lib.filter (h: h.id_hash != host.id_hash) (lib.attrValues den.hosts.${host.system});
              fromClass = _: "ssh-host-key";
              intoClass = _: host.class;
              intoPath = _: [ ];
            }
          )
        ];

        expr = iceberg.environment.sessionVariables ? FROM_IGLOO;
        expected = true;
      }
    );

    test-forward-each-filter-excludes-self = denTest (
      { den, iceberg, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.hosts.x86_64-linux.iceberg = { };

        den.aspects.igloo.test-class.environment.sessionVariables.FROM_IGLOO = "yes";
        den.aspects.iceberg.test-class.environment.sessionVariables.FROM_ICEBERG = "yes";

        den.aspects.iceberg.includes = [
          (
            { host }:
            den.provides.forward {
              each = lib.filter (h: h.id_hash != host.id_hash) (lib.attrValues den.hosts.${host.system});
              fromClass = _: "test-class";
              intoClass = _: host.class;
              intoPath = _: [ ];
            }
          )
        ];

        expr = {
          hasIgloo = iceberg.environment.sessionVariables ? FROM_IGLOO;
          hasIceberg = iceberg.environment.sessionVariables ? FROM_ICEBERG;
        };
        expected = {
          hasIgloo = true;
          hasIceberg = false;
        };
      }
    );

    test-host-hm-aspects-forward-to-primary-user = denTest (
      { den, igloo, ... }:
      {
        den.schema.user.classes = [ "homeManager" ];
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # Host-level aspect defines homeManager config
        # tux does NOT explicitly include this
        den.aspects.shared-hm = {
          homeManager.programs.git.enable = true;
        };

        # Forward: collect all homeManager content from host resolution,
        # inject into primary user's home-manager path
        den.aspects.igloo.includes = [
          den.aspects.shared-hm
          (
            { host }:
            let
              primaryUser =
                lib.findFirst (u: true) # first user as "primary"
                  null
                  (lib.attrValues host.users);
            in
            lib.optionalAttrs (primaryUser != null) (
              den.provides.forward {
                each = lib.singleton host;
                fromAspect = h: den.lib.parametric.fixedTo { host = h; } h.aspect;
                fromClass = _: "homeManager";
                intoClass = _: host.class;
                intoPath = _: [
                  "home-manager"
                  "users"
                  primaryUser.userName
                ];
              }
            )
          )
        ];

        expr = igloo.home-manager.users.tux.programs.git.enable;
        expected = true;
      }
    );

    test-forward-hm-from-other-host-to-local-user = denTest (
      { den, iceberg, ... }:
      {
        den.schema.user.classes = [ "homeManager" ];
        den.hosts.x86_64-linux.igloo = { };
        den.hosts.x86_64-linux.iceberg.users.pingu = { };

        # igloo has homeManager aspects — pingu on iceberg doesn't include them
        den.aspects.igloo.includes = [ den.aspects.igloo-hm-stuff ];
        den.aspects.igloo-hm-stuff.homeManager.programs.firefox.enable = true;

        # iceberg forwards igloo's homeManager content into pingu
        den.aspects.iceberg.includes = [
          (
            { host }:
            let
              igloo = den.hosts.x86_64-linux.igloo;
              user = lib.head (lib.attrValues host.users);
            in
            den.provides.forward {
              each = lib.singleton igloo;
              fromClass = _: "homeManager";
              intoClass = _: host.class;
              intoPath = _: [
                "home-manager"
                "users"
                user.userName
              ];
            }
          )
        ];

        expr = iceberg.home-manager.users.pingu.programs.firefox.enable;
        expected = true;
      }
    );

    test-forward-carries-source-context-data = denTest (
      { den, iceberg, ... }:
      {
        den.schema.user.classes = [ "homeManager" ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg = { };

        # igloo has an aspect with a custom class carrying host-specific data
        den.aspects.igloo.includes = [ den.aspects.igloo-identity ];
        den.aspects.igloo-identity =
          { host }:
          {
            host-identity.environment.sessionVariables.SOURCE_HOST = host.hostName;
          };

        # iceberg pulls igloo's host-identity class content into its own nixos
        den.aspects.iceberg.includes = [
          (
            { host }:
            den.provides.forward {
              each = lib.singleton den.hosts.x86_64-linux.igloo;
              fromClass = _: "host-identity";
              intoClass = _: host.class;
              intoPath = _: [ ];
            }
          )
        ];

        # Verify the forwarded value actually comes from igloo's context
        expr = iceberg.environment.sessionVariables.SOURCE_HOST;
        expected = "igloo";
      }
    );

  };
}
