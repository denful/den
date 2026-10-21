# The "Defining your own entity kind" guide, as tests: a kind that inherits the
# shared base `den.schema.conf`, a registry of its instances built with
# `mkInstanceType`, a policy that resolves each instance as an entity, and
# kind-level `includes` that fire once per instance.
{ denTest, lib, ... }:
let
  organizations =
    { den, lib, ... }:
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
        schema.conf.options.owner = lib.mkOption {
          type = lib.types.str;
          default = "ops";
        };

        schema.organization = {
          inherits = [ den.schema.conf ];
          options.label = lib.mkOption { type = lib.types.str; };
        };

        organizations = {
          acme.label = "Acme";
          globex.label = "Globex";
        };
      };
    };
in
{
  flake.tests.c3.custom-entity-kind = {

    test-registry-instance-inherits-conf = denTest (
      { config, ... }:
      {
        imports = [ organizations ];
        expr = {
          inherit (config.den.organizations.acme) name label owner;
          hasAspect = config.den.organizations.acme ? hasAspect;
        };
        expected = {
          name = "acme";
          label = "Acme";
          owner = "ops";
          hasAspect = true;
        };
      }
    );

    test-strict-kind-refuses-undeclared-attribute = denTest (
      { den, config, ... }:
      {
        imports = [ organizations ];
        den.schema.organization.isStrict = true;
        den.organizations.acme.lable = "typo";
        expr = (builtins.tryEval (builtins.deepSeq config.den.organizations.acme.label true)).success;
        expected = false;
      }
    );

    # flake -> organization: each instance becomes an entity scope, and the
    # kind's own includes fire once per instance with `organization` bound
    test-kind-includes-fire-per-instance = denTest (
      { den, config, ... }:
      {
        imports = [ organizations ];
        den.policies.to-organizations =
          _:
          lib.mapAttrsToList (
            _: organization: den.lib.policy.resolve.to "organization" { inherit organization; }
          ) config.den.organizations;

        den.aspects.org-dns =
          { organization, ... }:
          {
            dns.records.${organization.name} = organization.label;
          };
        den.schema.organization.includes = [ den.aspects.org-dns ];

        den.policies.collect-dns = _: [
          (den.lib.policy.instantiate {
            name = "dns";
            class = "dns";
            instantiate =
              { modules, ... }:
              (lib.evalModules {
                modules = modules ++ [
                  {
                    options.records = lib.mkOption {
                      type = lib.types.attrsOf lib.types.str;
                      default = { };
                    };
                  }
                ];
              }).config.records;
            intoAttr = [ "dns" ];
          })
        ];
        den.schema.flake.includes = [
          den.policies.to-organizations
          den.policies.collect-dns
        ];

        expr = config.flake.dns;
        expected = {
          acme = "Acme";
          globex = "Globex";
        };
      }
    );

    # a nested kind: `site` under `organization`, resolved from the parent's
    # scope; content in a site scope sees both bindings
    test-nested-kind-sees-parent = denTest (
      { den, config, ... }:
      {
        imports = [ organizations ];
        den.schema.site.parent = "organization";
        den.organizations.acme.sites = [ { name = "hq"; } ];
        den.schema.organization.options.sites = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [ ];
        };

        den.policies.to-organizations =
          _:
          lib.mapAttrsToList (
            _: organization: den.lib.policy.resolve.to "organization" { inherit organization; }
          ) config.den.organizations;
        den.policies.organization-to-sites =
          { organization, ... }:
          map (site: den.lib.policy.resolve.to "site" { inherit site; }) organization.sites;
        den.schema.organization.includes = [ den.policies.organization-to-sites ];

        den.aspects.site-dns =
          { organization, site, ... }:
          {
            dns.records."${site.name}.${organization.name}" = organization.label;
          };
        den.schema.site.includes = [ den.aspects.site-dns ];

        den.policies.collect-dns = _: [
          (den.lib.policy.instantiate {
            name = "dns";
            class = "dns";
            instantiate =
              { modules, ... }:
              (lib.evalModules {
                modules = modules ++ [
                  {
                    options.records = lib.mkOption {
                      type = lib.types.attrsOf lib.types.str;
                      default = { };
                    };
                  }
                ];
              }).config.records;
            intoAttr = [ "dns" ];
          })
        ];
        den.schema.flake.includes = [
          den.policies.to-organizations
          den.policies.collect-dns
        ];

        expr = config.flake.dns;
        expected = {
          "hq.acme" = "Acme";
        };
      }
    );

  };
}
