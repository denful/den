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

    test-has-classes = denTest (
      { den, ... }:
      {
        expr = den ? classes;
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

  };
}
