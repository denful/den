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
        comp = fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
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
          hasNixos = (builtins.head result.value) ? nixos;
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
        comp = fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
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

    # Nested keys are classified but not auto-walked — require explicit includes.
    test-nested-aspect-not-auto-emitted = denTest (
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
        comp = fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
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

        # Nested "servers" is NOT auto-emitted — 0 class imports from it
        expr = builtins.length (
          (builtins.foldl' (
            acc: sd:
            lib.zipAttrsWith (_: builtins.concatLists) [
              acc
              sd
            ]
          ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
        );
        expected = 0;
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
        comp = fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
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
          name = (builtins.head result.value).name;
        };
        expected = {
          importsCount = 1;
          name = "misc";
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
        comp = fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
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
        comp = fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
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
        comp = fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
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
        comp = fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
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

        expr = (builtins.head result.value).name;
        expected = "safe";
      }
    );

    # Freeform data key whose sub-key name collides with a registered class
    # must NOT be treated as a nested aspect.  Regression test: git.user data
    # was misclassified because "user" matched den.classes.user.
    test-class-name-collision-not-nested = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "dev";
          meta = { };
          nixos = {
            networking.hostName = "test";
          };
          # "git" is not a class; its child "user" collides with den.classes.user
          # but the value is flat data, not a module — must be ignored.
          git = {
            user = {
              name = "Alice";
              email = "alice@example.com";
            };
          };
          includes = [ ];
        };
        comp = fx.send "resolve" {
          inherit aspect;
          identity = den.lib.aspects.fx.identity.key aspect;
          ctx = { };
        };
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
        den.classes.user.description = "User environment";

        # Only nixos produces an import; git.user data is not dispatched as user class
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
