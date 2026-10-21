# A custom entity kind's instances carry `resolved`, so the `hasAspect` they
# inherit from `den.schema.conf` answers instead of throwing "has no
# config.resolved". den's `mkInstanceType` supplies it for every entity kind,
# as it does for host, user and home.
{ denTest, ... }:
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
        schema.organization = {
          inherits = [ den.schema.conf ];
          options.class = lib.mkOption {
            type = lib.types.str;
            default = "org";
          };
          includes = [ den.aspects.common ];
        };
        organizations.acme = { };

        classes.org.description = "Organization content";
        aspects.common.org.tags = [ "common" ];
        aspects.other.org.tags = [ "other" ];
      };
    };
in
{
  flake.tests.deadbugs.custom-kind-resolved = {

    test-instance-has-resolved = denTest (
      { config, ... }:
      {
        imports = [ organizations ];
        expr = config.den.organizations.acme ? resolved;
        expected = true;
      }
    );

    test-has-aspect-included = denTest (
      { den, config, ... }:
      {
        imports = [ organizations ];
        expr = config.den.organizations.acme.hasAspect den.aspects.common;
        expected = true;
      }
    );

    test-has-aspect-absent = denTest (
      { den, config, ... }:
      {
        imports = [ organizations ];
        expr = config.den.organizations.acme.hasAspect den.aspects.other;
        expected = false;
      }
    );

    test-strict-kind-accepts-resolved-options = denTest (
      { den, config, ... }:
      {
        imports = [ organizations ];
        den.schema.organization.isStrict = true;
        expr = config.den.organizations.acme.hasAspect den.aspects.common;
        expected = true;
      }
    );

  };
}
