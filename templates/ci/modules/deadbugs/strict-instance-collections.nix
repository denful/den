# An instance's own `includes` / `excludes` are read for every entity kind, so a
# strict kind must accept them: they are declared on `den.schema.conf`, not
# absorbed by the open instance type's freeform.
{ denTest, lib, ... }:
let
  organizations =
    {
      den,
      lib,
      config,
      ...
    }:
    {
      options.den.organizations = lib.mkOption {
        type = lib.types.attrsOf (
          den.lib.schema.mkInstanceType {
            strict = den.schema.organization.isStrict;
          } den.schema.organization
        );
        default = { };
      };

      config.den = {
        schema.organization = {
          inherits = [ den.schema.conf ];
          isStrict = true;
          includes = [
            den.aspects.common
            den.policies.collect-org
          ];
        };
        schema.flake.includes = [ den.policies.to-organizations ];

        organizations.acme.includes = [ den.aspects.extra ];
        organizations.globex.excludes = [ den.aspects.common ];

        classes.org.description = "Organization content";
        aspects.common.org.tags = [ "common" ];
        aspects.extra.org.tags = [ "extra" ];

        policies.to-organizations =
          _:
          lib.mapAttrsToList (
            _: organization: den.lib.policy.resolve.to "organization" { inherit organization; }
          ) config.den.organizations;

        policies.collect-org =
          { organization, ... }:
          [
            (den.lib.policy.instantiate {
              name = "org-${organization.name}";
              class = "org";
              instantiate =
                { modules, ... }:
                (lib.evalModules {
                  modules = modules ++ [
                    {
                      options.tags = lib.mkOption {
                        type = lib.types.listOf lib.types.str;
                        default = [ ];
                      };
                    }
                  ];
                }).config.tags;
              intoAttr = [
                "orgTags"
                organization.name
              ];
            })
          ];
      };
    };
in
{
  flake.tests.deadbugs.strict-instance-collections = {

    test-strict-host-instance-includes = denTest (
      { den, igloo, ... }:
      {
        den.schema.host.isStrict = true;
        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          includes = [ den.aspects.wanted ];
        };
        den.aspects.wanted.nixos.networking.domain = "wanted.example";

        expr = igloo.networking.domain;
        expected = "wanted.example";
      }
    );

    test-strict-host-instance-excludes = denTest (
      { den, igloo, ... }:
      {
        den.schema.host.isStrict = true;
        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          excludes = [ den.aspects.unwanted ];
        };
        den.aspects.igloo.includes = [ den.aspects.unwanted ];
        den.aspects.unwanted.nixos.networking.domain = "unwanted.example";

        expr = igloo.networking.domain;
        expected = null;
      }
    );

    test-strict-custom-kind-instance-collections = denTest (
      { config, ... }:
      {
        imports = [ organizations ];
        expr = lib.mapAttrs (_: lib.sort lib.lessThan) config.flake.orgTags;
        expected = {
          acme = [
            "common"
            "extra"
          ];
          globex = [ ];
        };
      }
    );

    test-strict-still-refuses-undeclared = denTest (
      { den, ... }:
      {
        den.schema.host.isStrict = true;
        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          includez = [ ];
        };

        expr = den.hosts.x86_64-linux.igloo.includez;
        expectedError = {
          type = "ThrownError";
          msg = "STRICT MODE: \"includez\" is not declared on host";
        };
      }
    );

  };
}
