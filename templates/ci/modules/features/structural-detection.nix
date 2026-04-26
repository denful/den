{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.structural-detection = {

    # When schema registries are empty, all non-structural keys are classes (backward compat).
    test-empty-registry-all-classes = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "base";
          meta = { };
          nixos = {
            networking.hostName = "test";
          };
          includes = [ ];
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
      in
      {
        expr = {
          hasNixos = result.value ? nixos;
          importsLength = builtins.length (result.state.imports null);
        };
        expected = {
          hasNixos = true;
          importsLength = 1;
        };
      }
    );

    # Registered class key emits emit-class — produces an import.
    test-registered-class-emits = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "base";
          meta = { };
          nixos = {
            networking.hostName = "igloo";
          };
          includes = [ ];
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
      in
      {
        den.classes.nixos.description = "NixOS system configuration";

        expr = builtins.length (result.state.imports null) > 0;
        expected = true;
      }
    );

    # Registered trait key emits emit-trait (no-op handler — no crash).
    test-registered-trait-no-crash = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "netstack";
          meta = { };
          firewall = {
            enable = true;
          };
          includes = [ ];
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
        result = fx.handle {
          handlers =
            den.lib.aspects.fx.pipeline.defaultHandlers {
              class = "nixos";
              ctx = { };
            }
            // {
              # Override emit-class to track calls
              "emit-class" =
                { param, state }:
                {
                  resume = null;
                  inherit state;
                };
            };
          state = den.lib.aspects.fx.pipeline.defaultState // {
            traitRegistry = den.traits or { };
          };
        } comp;
      in
      {
        den.traits.firewall = {
          description = "Firewall rules";
          collection = "list";
        };

        # Should resolve without error — the emit-trait handler is a no-op.
        expr = result.value.name;
        expected = "netstack";
      }
    );

    # Trait key classified correctly — not emitted as a class.
    test-trait-not-class = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        classEmitted = builtins.unsafeGetAttrPos "never-used" { never-used = true; } == null;
        aspect = {
          name = "netstack";
          meta = { };
          firewall = {
            enable = true;
          };
          nixos = {
            networking.firewall.enable = true;
          };
          includes = [ ];
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
      in
      {
        den.classes.nixos.description = "NixOS";
        den.traits.firewall = {
          description = "Firewall rules";
        };

        # Only nixos should produce an import, not firewall
        expr = builtins.length (result.state.imports null);
        expected = 1;
      }
    );

    # classifyKeys returns correct buckets with populated registries.
    test-classify-keys-buckets = denTest (
      { den, ... }:
      let
        classifyKeys = den.lib.aspects.fx.aspect.classifyKeys or null;
      in
      {
        den.classes.nixos.description = "NixOS";
        den.traits.firewall.description = "Firewall";

        # classifyKeys is internal — test through pipeline behavior instead.
        # An aspect with nixos (class) + firewall (trait) + unknown key.
        expr =
          let
            fx = den.lib.fx;
            aspect = {
              name = "mixed";
              meta = { };
              nixos = { };
              firewall = {
                enable = true;
              };
              includes = [ ];
            };
            comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
            result = fx.handle {
              handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
                class = "nixos";
                ctx = { };
              };
              state = den.lib.aspects.fx.pipeline.defaultState;
            } comp;
          in
          {
            # Only nixos (class) produces imports; firewall (trait) is no-op
            importsCount = builtins.length (result.state.imports null);
            resolvedOk = result.value.name == "mixed";
          };
        expected = {
          importsCount = 1;
          resolvedOk = true;
        };
      }
    );

    # Nested aspect detection: unknown key with class sub-keys recurses.
    test-nested-aspect-detection = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "parent";
          meta = { };
          # "servers" is not a registered class or trait, but has a "nixos" sub-key
          servers = {
            nixos = {
              services.nginx.enable = true;
            };
          };
          includes = [ ];
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
      in
      {
        den.classes.nixos.description = "NixOS";

        # The nested "servers" aspect should recurse and emit its "nixos" sub-key as a class
        expr = builtins.length (result.state.imports null) > 0;
        expected = true;
      }
    );

    # Freeform key (unknown, no class/trait sub-keys) doesn't crash.
    test-freeform-ignored = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "misc";
          meta = { };
          nixos = {
            networking.hostName = "test";
          };
          randomThing = "hello";
          includes = [ ];
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
      in
      {
        den.classes.nixos.description = "NixOS";

        # Only the class "nixos" produces an import; randomThing is freeform → ignored
        expr = {
          importsCount = builtins.length (result.state.imports null);
          name = result.value.name;
        };
        expected = {
          importsCount = 1;
          name = "misc";
        };
      }
    );

    # Default pipeline state has traits and deferredTraits fields.
    test-default-state-has-trait-fields = denTest (
      { den, ... }:
      {
        expr = {
          hasTraits = den.lib.aspects.fx.pipeline.defaultState ? traits;
          hasDeferredTraits = den.lib.aspects.fx.pipeline.defaultState ? deferredTraits;
        };
        expected = {
          hasTraits = true;
          hasDeferredTraits = true;
        };
      }
    );

    # Backward compat: with batteries (auto-registered classes), class keys still emit.
    test-backward-compat-with-batteries = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "igloo";
          meta = { };
          nixos = {
            networking.hostName = "igloo";
          };
          includes = [ ];
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
      in
      {
        # Batteries auto-register nixos as a class; aspect should still produce imports.
        expr = builtins.length (result.state.imports null) > 0;
        expected = true;
      }
    );

  };
}
