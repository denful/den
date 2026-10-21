# Entity-isolation marker + isolation-aware extraction (spec 2026-06-11).
{ denTest, ... }:
{
  flake.tests.c3.entity-isolation = {

    # Kind-level marker: declared via gen-schema collection, default false.
    test-isolated-marker = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.iso-kind = {
          isEntity = true;
          parent = "host";
          isolated = true;
        };

        expr = {
          iso = config.den.schema.iso-kind.isolated;
          host = config.den.schema.host.isolated;
        };
        expected = {
          iso = true;
          host = false;
        };
      }
    );

    # The marker alone must not flip the computed isEntity heuristic.
    test-isolated-alone-not-entity = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.marker-only.isolated = true;

        expr = config.den.schema.marker-only.isEntity;
        expected = false;
      }
    );

    # An isolated child's nixos-authored content must NOT be absorbed into
    # the parent's own nixos config (the cortex microvm.guest leak).
    test-isolated-content-not-absorbed = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        guestEntity = {
          name = "guest";
          system = "x86_64-linux";
          class = "nixos";
          intoAttr = [ ];
          users = { };
          aspect = den.aspects.guest-aspect;
        };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.iso-kind = {
          isEntity = true;
          parent = "host";
          isolated = true;
        };
        # Gate on the parent's name so the policy does not re-fire inside the
        # guest scope. Bind only the iso-kind record — rebinding `host` to the
        # guest would trigger the host home-env synthesis (which the bare guest
        # record cannot satisfy) and is unnecessary: the iso-kind scope inherits
        # the parent `host` (igloo) from the enriched ctx, and isolation gates
        # whether its nixos content leaks back into igloo.
        den.policies.resolve-iso-child =
          { host, ... }:
          lib.optionals (host.name == "igloo") [
            (den.lib.policy.resolve.to "iso-kind" {
              iso-kind = guestEntity;
            })
          ];
        den.schema.host.includes = [ den.policies.resolve-iso-child ];
        den.aspects.guest-aspect.nixos.boot.kernelModules = [ "guest-only-module" ];

        # igloo carries nixpkgs hardware defaults (atkbd/loop), so assert the
        # guest's module specifically does NOT leak in rather than equality to [].
        expr = lib.elem "guest-only-module" igloo.boot.kernelModules;
        expected = false;
      }
    );

    # SPIKE falsifier: a route registered inside the isolated guest scope with
    # appendToParent delivers the guest subtree's nixos exactly once at the
    # parent path — and the parent's own toplevel stays clean.
    test-isolated-delivery-exactly-once = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        guestEntity = {
          name = "guest";
          system = "x86_64-linux";
          class = "nixos";
          intoAttr = [ ];
          users = { };
          aspect = den.aspects.guest-aspect;
        };
        # Fires inside the guest scope (resolve includes): sourceScopeId
        # defaults to the guest scope = collection root. Gated against
        # re-fire in nested sub-scopes where it would self-deliver.
        deliverPolicy = den.lib.policy.mkPolicy "deliver-iso" (
          { ... }@args:
          lib.optionals (!(args ? user) && !(args ? home)) [
            (den.lib.policy.route {
              fromClass = "nixos";
              intoClass = "nixos";
              collectSubtree = true;
              appendToParent = true;
              path = [
                "microvm"
                "vms"
                "guest"
                "config"
              ];
            })
          ]
        );
        # Freeform slot on the parent so delivered content has a landing path.
        microvmSlot =
          { lib, ... }:
          {
            options.microvm.vms = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options.config = lib.mkOption {
                    type = lib.types.submoduleWith {
                      modules = [
                        { config._module.freeformType = lib.types.lazyAttrsOf lib.types.anything; }
                      ];
                    };
                    default = { };
                  };
                }
              );
              default = { };
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
        den.policies.resolve-iso-child =
          { host, ... }:
          lib.optionals (host.name == "igloo") [
            (den.lib.policy.resolve.to.withIncludes "iso-kind" [ deliverPolicy ] {
              iso-kind = guestEntity;
            })
          ];
        den.schema.host.includes = [ den.policies.resolve-iso-child ];
        den.aspects.igloo.nixos.imports = [ microvmSlot ];
        den.aspects.guest-aspect.nixos.boot.kernelModules = [ "guest-only-module" ];

        expr = {
          delivered = lib.elem "guest-only-module" igloo.microvm.vms.guest.config.boot.kernelModules;
          leaked = lib.elem "guest-only-module" igloo.boot.kernelModules;
        };
        expected = {
          delivered = true;
          leaked = false;
        };
      }
    );

    test-isolated-delivery-includes-os-class = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        guestEntity = {
          name = "guest";
          system = "x86_64-linux";
          class = "nixos";
          intoAttr = [ ];
          users = { };
          aspect = den.aspects.guest-aspect;
        };
        # Fires inside the guest scope (resolve includes): sourceScopeId
        # defaults to the guest scope = collection root. Gated against
        # re-fire in nested sub-scopes where it would self-deliver.
        deliverPolicy = den.lib.policy.mkPolicy "deliver-iso" (
          { ... }@args:
          lib.optionals (!(args ? user) && !(args ? home)) [
            (den.lib.policy.route {
              fromClass = "nixos";
              intoClass = "nixos";
              collectSubtree = true;
              appendToParent = true;
              path = [
                "microvm"
                "vms"
                "guest"
                "config"
              ];
            })
          ]
        );
        # Freeform slot on the parent so delivered content has a landing path.
        microvmSlot =
          { lib, ... }:
          {
            options.microvm.vms = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options.config = lib.mkOption {
                    type = lib.types.submoduleWith {
                      modules = [
                        { config._module.freeformType = lib.types.lazyAttrsOf lib.types.anything; }
                      ];
                    };
                    default = { };
                  };
                }
              );
              default = { };
            };
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.iso-kind = {
          isEntity = true;
          parent = "host";
          isolated = true;
          # As a real guest kind does: its curated includes carry den.default's
          # os-to-host, so the class alias registers in the guest scope.
          includes = [ den.policies.os-to-host ];
        };
        den.policies.resolve-iso-child =
          { host, ... }:
          lib.optionals (host.name == "igloo") [
            (den.lib.policy.resolve.to.withIncludes "iso-kind" [ deliverPolicy ] {
              iso-kind = guestEntity;
            })
          ];
        den.schema.host.includes = [ den.policies.resolve-iso-child ];
        den.aspects.igloo.nixos.imports = [ microvmSlot ];
        # Authored in the cross-platform `os` class: os-to-host routes it into the
        # guest's nixos, which the delivery route must carry to the parent slot.
        den.aspects.guest-aspect.os.boot.kernelModules = [ "guest-only-module" ];

        expr = {
          delivered = lib.elem "guest-only-module" igloo.microvm.vms.guest.config.boot.kernelModules;
          leaked = lib.elem "guest-only-module" igloo.boot.kernelModules;
        };
        expected = {
          delivered = true;
          leaked = false;
        };
      }
    );

    # A host-rooted collectSubtree route must NOT pull content from an isolated
    # descendant: parent and guest both author a shared `side-chan` class; only
    # the parent's own side-chan content may reach the route target path.
    test-host-route-skips-isolated = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        guestEntity = {
          name = "guest";
          system = "x86_64-linux";
          class = "nixos";
          intoAttr = [ ];
          users = { };
          aspect = den.aspects.guest-aspect;
        };
        microvmSlot =
          { lib, ... }:
          {
            options.microvm.vms = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options.config = lib.mkOption {
                    type = lib.types.submoduleWith {
                      modules = [
                        { config._module.freeformType = lib.types.lazyAttrsOf lib.types.anything; }
                      ];
                    };
                    default = { };
                  };
                }
              );
              default = { };
            };
          };
        # Host-scope route moving side-chan content into a parent path. Gated on
        # the parent name so it does not re-fire (and self-deliver) in the guest.
        collectPolicy =
          { host, ... }:
          lib.optionals (host.name == "igloo") [
            (den.lib.policy.route {
              fromClass = "side-chan";
              intoClass = "nixos";
              collectSubtree = true;
              path = [
                "microvm"
                "vms"
                "side"
                "config"
              ];
            })
          ];
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.classes.side-chan.description = "side channel test class";
        den.schema.iso-kind = {
          isEntity = true;
          parent = "host";
          isolated = true;
        };
        den.policies.resolve-iso-child =
          { host, ... }:
          lib.optionals (host.name == "igloo") [
            (den.lib.policy.resolve.to "iso-kind" {
              iso-kind = guestEntity;
            })
          ];
        den.policies.collect-side = collectPolicy;
        den.schema.host.includes = [
          den.policies.resolve-iso-child
          den.policies.collect-side
        ];
        den.aspects.igloo.nixos.imports = [ microvmSlot ];
        den.aspects.igloo.side-chan.boot.kernelModules = [ "host-side" ];
        den.aspects.guest-aspect.side-chan.boot.kernelModules = [ "guest-side" ];

        expr = {
          hostSide = lib.elem "host-side" igloo.microvm.vms.side.config.boot.kernelModules;
          guestSide = lib.elem "guest-side" igloo.microvm.vms.side.config.boot.kernelModules;
        };
        expected = {
          hostSide = true;
          guestSide = false;
        };
      }
    );
  };
}
