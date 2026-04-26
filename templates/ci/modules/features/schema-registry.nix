{ denTest, ... }:
{
  flake.tests.schema-registry = {
    test-class-declaration = denTest (
      { den, ... }:
      {
        den.schema.classes.nixos.description = "NixOS system configuration";

        expr = den.schema.classes.nixos.description;
        expected = "NixOS system configuration";
      }
    );

    test-class-forwardTo-default = denTest (
      { den, ... }:
      {
        den.schema.classes.nixos.description = "NixOS";

        expr = den.schema.classes.nixos.forwardTo;
        expected = null;
      }
    );

    test-trait-declaration = denTest (
      { den, ... }:
      {
        den.schema.traits.firewall = {
          description = "Firewall trait";
          collection = "map";
          partialOk = true;
        };

        expr = {
          inherit (den.schema.traits.firewall) description collection partialOk;
        };
        expected = {
          description = "Firewall trait";
          collection = "map";
          partialOk = true;
        };
      }
    );

    test-trait-defaults = denTest (
      { den, ... }:
      {
        den.schema.traits.firewall.description = "Firewall trait";

        expr = {
          inherit (den.schema.traits.firewall) collection partialOk;
        };
        expected = {
          collection = "list";
          partialOk = false;
        };
      }
    );

    test-trait-type-default = denTest (
      { den, ... }:
      {
        den.schema.traits.firewall.description = "Firewall trait";

        expr = den.schema.traits.firewall.type;
        expected = null;
      }
    );

    test-schema-has-classes = denTest (
      { den, ... }:
      {
        expr = den.schema ? classes;
        expected = true;
      }
    );

    test-schema-has-traits = denTest (
      { den, ... }:
      {
        expr = den.schema ? traits;
        expected = true;
      }
    );

    test-existing-schema-conf = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = den.schema ? conf && den.schema ? host && den.schema ? user && den.schema ? home;
        expected = true;
      }
    );

    test-collision-error = denTest (
      { den, ... }:
      {
        den.schema.classes.shared.description = "A class";
        den.schema.traits.shared.description = "A trait";

        expr = den.schema.classes.shared.description;
        expectedError = {
          type = "ThrownError";
          msg = "cannot be both a class and a trait";
        };
      }
    );
  };
}
