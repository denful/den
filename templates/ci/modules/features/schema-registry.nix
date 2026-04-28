{ denTest, ... }:
{
  flake.tests.schema-registry = {
    test-class-declaration = denTest (
      { den, ... }:
      {
        den.classes.nixos.description = "NixOS system configuration";

        expr = den.classes.nixos.description;
        expected = "NixOS system configuration";
      }
    );

    test-class-forwardTo-default = denTest (
      { den, ... }:
      {
        den.classes.nixos.description = "NixOS";

        expr = den.classes.nixos.forwardTo;
        expected = null;
      }
    );

    test-trait-declaration = denTest (
      { den, ... }:
      {
        den.traits.firewall = {
          description = "Firewall trait";
          collection = "map";
          partialOk = true;
        };

        expr = {
          inherit (den.traits.firewall) description collection partialOk;
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
        den.traits.firewall.description = "Firewall trait";

        expr = {
          inherit (den.traits.firewall) collection partialOk;
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
        den.traits.firewall.description = "Firewall trait";

        expr = den.traits.firewall.type;
        expected = null;
      }
    );

    test-has-classes = denTest (
      { den, ... }:
      {
        expr = den ? classes;
        expected = true;
      }
    );

    test-has-traits = denTest (
      { den, ... }:
      {
        expr = den ? traits;
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

    # Auto-registration tests: batteries register classes without manual declaration
    test-auto-nixos = denTest (
      { den, ... }:
      {
        expr = den.classes.nixos.description;
        expected = "NixOS system configuration";
      }
    );

    test-auto-darwin = denTest (
      { den, ... }:
      {
        expr = den.classes.darwin.description;
        expected = "nix-darwin system configuration";
      }
    );

    test-auto-os = denTest (
      { den, ... }:
      {
        expr = den.classes.os.description;
        expected = "Convenience class forwarding to both nixos and darwin";
      }
    );

    test-auto-user = denTest (
      { den, ... }:
      {
        expr = den.classes.user.description;
        expected = "Lightweight user environment forwarding to OS users.users";
      }
    );

    test-auto-classes-exist = denTest (
      { den, ... }:
      {
        expr = builtins.all (c: den.classes ? ${c}) [
          "nixos"
          "darwin"
          "os"
          "user"
        ];
        expected = true;
      }
    );

    test-auto-forwardTo-null = denTest (
      { den, ... }:
      {
        expr = den.classes.nixos.forwardTo;
        expected = null;
      }
    );

    test-collision-error = denTest (
      { den, ... }:
      {
        den.classes.shared.description = "A class";
        den.traits.shared.description = "A trait";

        expr = den.classes.shared.description;
        expectedError = {
          type = "ThrownError";
          msg = "cannot be both a class and a trait";
        };
      }
    );

    # Namespace-level trait/class declarations merge into den.traits/den.classes
    test-namespace-trait-merges = denTest (
      { den, ... }:
      {
        den.ful.test-ns.traits.monitoring = {
          description = "Monitoring trait";
          collection = "list";
        };

        expr = {
          inherit (den.traits.monitoring) description collection;
        };
        expected = {
          description = "Monitoring trait";
          collection = "list";
        };
      }
    );

    test-namespace-class-merges = denTest (
      { den, ... }:
      {
        den.ful.test-ns.classes.container = {
          description = "Container class";
        };

        expr = den.classes.container.description;
        expected = "Container class";
      }
    );

    test-namespace-traits-preserve-existing = denTest (
      { den, ... }:
      {
        den.traits.firewall.description = "Firewall trait";
        den.ful.test-ns.traits.monitoring = {
          description = "Monitoring trait";
        };

        expr = {
          firewall = den.traits.firewall.description;
          monitoring = den.traits.monitoring.description;
        };
        expected = {
          firewall = "Firewall trait";
          monitoring = "Monitoring trait";
        };
      }
    );

    test-cross-namespace-trait-merge = denTest (
      { den, ... }:
      {
        den.ful.ns-a.traits.shared-trait = {
          description = "Shared trait";
          collection = "map";
        };
        den.ful.ns-b.traits.shared-trait = {
          description = "Shared trait";
          collection = "map";
        };

        expr = den.traits.shared-trait.description;
        expected = "Shared trait";
      }
    );

    # Aspect-level trait/class installation tests
    test-aspect-trait-install = denTest (
      { den, ... }:
      {
        den.aspects.netstack.traits.firewall = {
          description = "Firewall rules";
          collection = "list";
        };

        expr = {
          inherit (den.traits.firewall) description collection;
        };
        expected = {
          description = "Firewall rules";
          collection = "list";
        };
      }
    );

    test-aspect-class-install = denTest (
      { den, ... }:
      {
        den.aspects.gui.classes.wayland = {
          description = "Wayland compositor configuration";
        };

        expr = den.classes.wayland.description;
        expected = "Wayland compositor configuration";
      }
    );

    test-aspect-trait-merge-compatible = denTest (
      { den, ... }:
      {
        den.aspects.netstack.traits.firewall = {
          description = "Firewall rules";
          collection = "list";
        };
        den.aspects.security.traits.firewall = {
          description = "Firewall rules";
          collection = "list";
        };

        expr = den.traits.firewall.description;
        expected = "Firewall rules";
      }
    );

    test-aspect-traits-not-freeform = denTest (
      { den, ... }:
      {
        den.aspects.netstack = {
          traits.firewall = {
            description = "Firewall rules";
          };
          nixos = { };
        };

        expr = builtins.attrNames (
          builtins.removeAttrs den.aspects.netstack [
            "name"
            "description"
            "meta"
            "includes"
            "provides"
            "policies"
            "policies"
            "traits"
            "classes"
            "_module"
            "_"
            "__functor"
          ]
        );
        expected = [ "nixos" ];
      }
    );
  };
}
