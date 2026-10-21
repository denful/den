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

    # route `reinstantiate`: deliver collected modules VERBATIM into a target
    # whose option `merge` RE-INSTANTIATES them as their own module set together
    # with base modules (e.g. microvm.nix's `microvm.vms.<n>.config`, whose
    # merge re-runs eval-config). The flag keeps each collected wrapper's keyed
    # module intact instead of pre-evaluating it in an isolated freeform
    # evalModules. A guest module that READS a base-module default must see it —
    # proving the route shipped live MODULES re-evaluated WITH the base, not a
    # pre-frozen resolved attrset. Pre-flag (nestPlain) the read has no
    # `fromBase` default in scope and the delivery THROWS. Hand-rolled (no
    # delivered-child policy): a bare resolve into an isolated guest scope + a
    # delivery route carrying reinstantiate, into a faithfully re-instantiating
    # slot. A freeform stub slot (test-isolated-delivery-exactly-once) cannot
    # exercise this — it stores defs without re-evaluating them.
    test-route-reinstantiate-base-context = denTest (
      { den, igloo, ... }:
      let
        guestEntity = {
          name = "guest";
          system = "x86_64-linux";
          class = "nixos";
          intoAttr = [ ];
          users = { };
          aspect = den.aspects.guest-aspect;
        };
        # Delivery route registered INSIDE the guest scope (collection root),
        # gated against re-fire in nested sub-scopes. `reinstantiate = true`
        # ships the keyed wrappers verbatim.
        deliverPolicy = den.lib.policy.mkPolicy "deliver-reinst" (
          { ... }@args:
          lib.optionals (!(args ? user) && !(args ? home)) [
            (den.lib.policy.route {
              fromClass = "nixos";
              intoClass = "nixos";
              collectSubtree = true;
              appendToParent = true;
              reinstantiate = true;
              path = [
                "microvm"
                "vms"
                "guest"
                "config"
              ];
            })
          ]
        );
        # Base module of the target system: declares `fromBase` WITH A DEFAULT
        # (the analogue of NixOS boot.* defaults) and is freeform so authored
        # guest content lands.
        reinstantiatingBase =
          { lib, ... }:
          {
            options.fromBase = lib.mkOption {
              type = lib.types.str;
              default = "BASE-DEFAULT";
            };
            config._module.freeformType = lib.types.lazyAttrsOf lib.types.anything;
          };
        # A target slot whose `merge` re-runs evalModules over the delivered
        # defs together with the base module-list — exactly as microvm's
        # eval-config does. Consumer reads `.config.config.*`.
        reinstantiatingSlot =
          { lib, ... }:
          {
            options.microvm.vms = lib.mkOption {
              default = { };
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options.config = lib.mkOption {
                    default = null;
                    type = lib.types.nullOr (
                      lib.mkOptionType {
                        name = "reinstantiated NixOS config";
                        merge =
                          _loc: defs:
                          lib.evalModules {
                            modules = [ reinstantiatingBase ] ++ map (d: d.value) defs;
                          };
                      }
                    );
                  };
                }
              );
            };
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.iso-kind = {
          isEntity = true;
          parent = "host";
          isolated = true;
        };
        den.policies.resolve-reinst-child =
          { host, ... }:
          lib.optionals (host.name == "igloo") [
            (den.lib.policy.resolve.to.withIncludes "iso-kind" [ deliverPolicy ] {
              iso-kind = guestEntity;
            })
          ];
        den.schema.host.includes = [ den.policies.resolve-reinst-child ];
        den.aspects.igloo.nixos.imports = [ reinstantiatingSlot ];
        den.aspects.guest-aspect.nixos =
          { config, ... }:
          {
            networking.hostName = "guest-vm";
            # Reads a default declared by a BASE module of the target system.
            echoed = config.fromBase;
          };

        # `.config.config` — first `.config` is the slot option, second is the
        # re-instantiated evalModules result's config.
        expr = {
          hn = igloo.microvm.vms.guest.config.config.networking.hostName;
          echoed = igloo.microvm.vms.guest.config.config.echoed;
        };
        expected = {
          hn = "guest-vm";
          echoed = "BASE-DEFAULT";
        };
      }
    );

  };
}
