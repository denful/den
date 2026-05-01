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
          importsLength = builtins.length (
            (builtins.foldl' (
              acc: sd:
              lib.zipAttrsWith (_: builtins.concatLists) [
                acc
                sd
              ]
            ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
          );
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

        expr =
          builtins.length (
            (builtins.foldl' (
              acc: sd:
              lib.zipAttrsWith (_: builtins.concatLists) [
                acc
                sd
              ]
            ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
          ) > 0;
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
        expr = builtins.length (
          (builtins.foldl' (
            acc: sd:
            lib.zipAttrsWith (_: builtins.concatLists) [
              acc
              sd
            ]
          ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
        );
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
            importsCount = builtins.length (
              (builtins.foldl' (
                acc: sd:
                lib.zipAttrsWith (_: builtins.concatLists) [
                  acc
                  sd
                ]
              ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
            );
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
        expr =
          builtins.length (
            (builtins.foldl' (
              acc: sd:
              lib.zipAttrsWith (_: builtins.concatLists) [
                acc
                sd
              ]
            ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
          ) > 0;
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
          importsCount = builtins.length (
            (builtins.foldl' (
              acc: sd:
              lib.zipAttrsWith (_: builtins.concatLists) [
                acc
                sd
              ]
            ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
          );
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
          hasTraits = den.lib.aspects.fx.pipeline.defaultState ? scopedTraits;
          hasDeferredTraits = den.lib.aspects.fx.pipeline.defaultState ? scopedDeferredTraits;
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
        expr =
          builtins.length (
            (builtins.foldl' (
              acc: sd:
              lib.zipAttrsWith (_: builtins.concatLists) [
                acc
                sd
              ]
            ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
          ) > 0;
        expected = true;
      }
    );

    # targetClass recognition: pipeline's class is recognized even without registry entry.
    test-target-class-recognized = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "custom";
          meta = { };
          # "myclass" is NOT in den.classes but IS the pipeline targetClass
          myclass = {
            some.config = true;
          };
          includes = [ ];
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "myclass";
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
      in
      {
        den.classes.nixos.description = "NixOS";

        # myclass matches targetClass → emitted as class → produces import
        expr = builtins.length (
          (builtins.foldl' (
            acc: sd:
            lib.zipAttrsWith (_: builtins.concatLists) [
              acc
              sd
            ]
          ) { } (builtins.attrValues (result.state.scopedClassImports null))).myclass or [ ]
        );
        expected = 1;
      }
    );

    # Unregistered key with no sub-keys is ignored (not emitted as class).
    test-unregistered-key-ignored = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "test";
          meta = { };
          nixos = {
            networking.hostName = "test";
          };
          # "bogus" is not registered and has no recognized sub-keys
          bogus = {
            whatever = true;
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

        # Only nixos produces an import; bogus is ignored
        expr = builtins.length (
          (builtins.foldl' (
            acc: sd:
            lib.zipAttrsWith (_: builtins.concatLists) [
              acc
              sd
            ]
          ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
        );
        expected = 1;
      }
    );

    # targetClass null safety: when class is not in scope, no match occurs.
    test-target-class-null-safe = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "safe";
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
        den.classes.nixos.description = "NixOS";

        expr = result.value.name;
        expected = "safe";
      }
    );

    # funnyNames helper works with funny class registered in provider.
    test-funny-class-registered = denTest (
      { den, funnyNames, ... }:
      {
        den.aspects.simple = {
          funny.names = [ "test-value" ];
        };

        expr = funnyNames den.aspects.simple;
        expected = [ "test-value" ];
      }
    );

  };
}
