# Tests for the diag library's capture path.
# Verifies captureWithPaths produces correct trace entries via fx.send "resolve".
{
  denTest,
  lib,
  ...
}:
{
  flake.tests.fx-diag-capture = {

    test-capture-basic = denTest (
      { den, ... }:
      let
        root = {
          name = "root";
          meta.aspect-chain = [ ];
          nixos = {
            a = 1;
          };
          includes = [
            {
              name = "child";
              meta.aspect-chain = [ ];
              nixos = {
                b = 2;
              };
              includes = [ ];
            }
          ];
        };
        result = den.lib.capture.captureWithPaths [ "nixos" ] root;
      in
      {
        expr = {
          entryCount = builtins.length result.entries;
          names = map (e: e.name) result.entries;
          hasPathsByClass = result.pathsByClass ? nixos;
        };
        expected = {
          entryCount = 2;
          names = [
            "child"
            "root"
          ];
          hasPathsByClass = true;
        };
      }
    );

    test-capture-exclude = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx;
        target = {
          name = "drop";
          meta.aspect-chain = [ ];
        };
        root = {
          name = "root";
          meta = {
            aspect-chain = [ ];
            handleWith = fxLib.constraints.exclude target;
          };
          includes = [
            {
              name = "keep";
              meta.aspect-chain = [ ];
              nixos = {
                a = 1;
              };
              includes = [ ];
            }
            {
              name = "drop";
              meta.aspect-chain = [ ];
              nixos = {
                b = 2;
              };
              includes = [ ];
            }
          ];
        };
        result = den.lib.capture.captureWithPaths [ "nixos" ] root;
        excludedEntries = builtins.filter (e: e.excluded or false) result.entries;
      in
      {
        expr = {
          totalEntries = builtins.length result.entries;
          excludedCount = builtins.length excludedEntries;
        };
        expected = {
          totalEntries = 3;
          excludedCount = 1;
        };
      }
    );

    test-capture-parent-tracking = denTest (
      { den, ... }:
      let
        root = {
          name = "root";
          meta.aspect-chain = [ ];
          includes = [
            {
              name = "child";
              meta.aspect-chain = [ ];
              includes = [ ];
            }
          ];
        };
        result = den.lib.capture.captureWithPaths [ "nixos" ] root;
        childEntry = lib.findFirst (e: e.name == "child") null result.entries;
      in
      {
        expr = childEntry.parent;
        expected = "root";
      }
    );

    test-capture-nested-parent = denTest (
      { den, ... }:
      let
        root = {
          name = "root";
          meta.aspect-chain = [ ];
          includes = [
            {
              name = "child";
              meta.aspect-chain = [ ];
              includes = [
                {
                  name = "grandchild";
                  meta.aspect-chain = [ ];
                  includes = [ ];
                }
              ];
            }
          ];
        };
        result = den.lib.capture.captureWithPaths [ "nixos" ] root;
        gcEntry = lib.findFirst (e: e.name == "grandchild") null result.entries;
      in
      {
        expr = gcEntry.parent;
        expected = "child";
      }
    );

    test-capture-paths-exclude-tombstones = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx;
        target = {
          name = "drop";
          meta.aspect-chain = [ ];
        };
        root = {
          name = "root";
          meta = {
            aspect-chain = [ ];
            handleWith = fxLib.constraints.exclude target;
          };
          includes = [
            {
              name = "keep";
              meta.aspect-chain = [ ];
              includes = [ ];
            }
            {
              name = "drop";
              meta.aspect-chain = [ ];
              includes = [ ];
            }
          ];
        };
        result = den.lib.capture.captureWithPaths [ "nixos" ] root;
        pathCount = builtins.length (builtins.attrNames (result.pathsByClass.nixos or { }));
      in
      {
        # root + keep = 2 paths, drop is tombstoned and excluded
        expr = pathCount;
        expected = 2;
      }
    );

    test-capture-multi-class = denTest (
      { den, ... }:
      let
        root = {
          name = "root";
          meta.aspect-chain = [ ];
          nixos = {
            a = 1;
          };
          homeManager = {
            b = 2;
          };
          includes = [ ];
        };
        result = den.lib.capture.captureWithPaths [
          "nixos"
          "homeManager"
        ] root;
      in
      {
        expr = {
          entryCount = builtins.length result.entries;
          hasNixosPaths = result.pathsByClass ? nixos;
          hasHmPaths = result.pathsByClass ? homeManager;
        };
        expected = {
          entryCount = 2;
          hasNixosPaths = true;
          hasHmPaths = true;
        };
      }
    );

    test-capture-handlers-field = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx;
        target = {
          name = "x";
          meta.aspect-chain = [ ];
        };
        root = {
          name = "root";
          meta = {
            aspect-chain = [ ];
            handleWith = fxLib.constraints.exclude target;
          };
          includes = [ ];
        };
        result = den.lib.capture.captureWithPaths [ "nixos" ] root;
        rootEntry = lib.findFirst (e: e.name == "root") null result.entries;
      in
      {
        expr = (rootEntry.handlers or [ ]) != [ ];
        expected = true;
      }
    );

  };
}
