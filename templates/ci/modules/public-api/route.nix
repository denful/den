# Tests for policy.route — Tier 1 class delivery.
{ denTest, lib, ... }:
let
  # Submodule option helper: declares an option at `name` with a listOf str type.
  mkListSubmodule =
    name:
    { lib, ... }:
    {
      options.${name} = lib.mkOption {
        type = lib.types.submoduleWith {
          modules = [
            {
              options.items = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
            }
          ];
        };
        default = { };
      };
    };
in
{
  flake.tests.route = {

    # Class route with path = [] — top-level injection into target class.
    test-route-class-toplevel = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.classes.custom.description = "Custom source class";

        den.policies.route-custom-toplevel =
          { host, ... }:
          [
            (den.lib.policy.route {
              fromClass = "custom";
              intoClass = host.class;
              path = [ ];
            })
          ];

        den.default.includes = [ den.policies.route-custom-toplevel ];

        den.aspects.igloo = {
          custom.networking.hostName = "routed-toplevel";
        };

        expr = igloo.networking.hostName;
        expected = "routed-toplevel";
      }
    );

    # Class route with path nesting — content injected at submodule path.
    test-route-class-into-subpath = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.classes.src.description = "Source class for subpath route";

        den.policies.route-src-subpath =
          { host, ... }:
          [
            (den.lib.policy.route {
              fromClass = "src";
              intoClass = host.class;
              path = [ "route-box" ];
            })
          ];

        den.default.includes = [ den.policies.route-src-subpath ];

        den.aspects.igloo = {
          nixos.imports = [ (mkListSubmodule "route-box") ];
          nixos.route-box.items = [ "from-nixos-owned" ];
          src.items = [ "from-src-class" ];
        };

        expr = lib.sort (a: b: a < b) igloo.route-box.items;
        expected = [
          "from-nixos-owned"
          "from-src-class"
        ];
      }
    );

    # Guarded route — guard false prevents injection.
    test-route-guarded-false = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.classes.guarded-src.description = "Guarded source class";

        den.policies.route-guarded-false =
          { host, ... }:
          [
            (den.lib.policy.route {
              fromClass = "guarded-src";
              intoClass = host.class;
              path = [ "guarded-box" ];
              guard = { options, ... }: options ? nonexistent-option-for-guard-test;
            })
          ];

        den.default.includes = [ den.policies.route-guarded-false ];

        den.aspects.igloo = {
          nixos.imports = [ (mkListSubmodule "guarded-box") ];
          nixos.guarded-box.items = [ "original" ];
          guarded-src.items = [ "should-not-appear" ];
        };

        expr = igloo.guarded-box.items;
        expected = [ "original" ];
      }
    );

    # Empty source — fromClass doesn't exist in source scope → no error.
    test-route-empty-source = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.classes.phantom.description = "Phantom class with no content";

        den.policies.route-phantom =
          { host, ... }:
          [
            (den.lib.policy.route {
              fromClass = "phantom";
              intoClass = host.class;
              path = [ ];
            })
          ];

        den.default.includes = [ den.policies.route-phantom ];

        den.aspects.igloo = {
          nixos.networking.hostName = "untouched";
        };

        expr = igloo.networking.hostName;
        expected = "untouched";
      }
    );

    # Guarded route with path — guard true + path nesting composition.
    test-route-guarded-with-path = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.classes.gp-src.description = "Guarded path source class";

        den.policies.route-guarded-path =
          { host, ... }:
          [
            (den.lib.policy.route {
              fromClass = "gp-src";
              intoClass = host.class;
              path = [ "gp-box" ];
              guard = { options, ... }: options ? gp-box;
            })
          ];

        den.default.includes = [ den.policies.route-guarded-path ];

        den.aspects.igloo = {
          nixos.imports = [ (mkListSubmodule "gp-box") ];
          nixos.gp-box.items = [ "nixos-owned" ];
          gp-src.items = [ "guarded-routed" ];
        };

        expr = lib.sort (a: b: a < b) igloo.gp-box.items;
        expected = [
          "guarded-routed"
          "nixos-owned"
        ];
      }
    );

    # policy.instantiate: host entity evaluation produces flake output
    test-instantiate-host = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos.networking.hostName = "instantiated";

        expr = config.flake.nixosConfigurations ? igloo;
        expected = true;
      }
    );

  };
}
