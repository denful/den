{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-identity = {

    test-aspectPath-with-provider = denTest (
      { den, ... }:
      let
        a = {
          name = "sub";
          meta = {
            provider = [ "monitoring" ];
          };
        };
      in
      {
        expr = den.lib.aspects.fx.identity.aspectPath a;
        expected = [
          "monitoring"
          "sub"
        ];
      }
    );

    test-aspectPath-no-provider = denTest (
      { den, ... }:
      let
        a = {
          name = "base";
          meta = { };
        };
      in
      {
        expr = den.lib.aspects.fx.identity.aspectPath a;
        expected = [ "base" ];
      }
    );

    test-pathKey = denTest (
      { den, ... }:
      {
        expr = den.lib.aspects.fx.identity.pathKey [
          "monitoring"
          "sub"
        ];
        expected = "monitoring/sub";
      }
    );

    test-toPathSet = denTest (
      { den, lib, ... }:
      let
        inherit (den.lib.aspects.fx.identity) pathKey;
        toPathSet =
          paths:
          builtins.listToAttrs (
            map (p: {
              name = pathKey p;
              value = true;
            }) paths
          );
      in
      {
        expr = toPathSet [
          [ "a" ]
          [
            "b"
            "c"
          ]
        ];
        expected = {
          "a" = true;
          "b/c" = true;
        };
      }
    );

    test-tombstone-shape = denTest (
      { den, ... }:
      let
        a = {
          name = "drop";
          meta = {
            provider = [ ];
          };
          includes = [ "x" ];
        };
        ts = den.lib.aspects.fx.identity.tombstone a { excludedFrom = "parent"; };
      in
      {
        expr = {
          name = ts.name;
          excluded = ts.meta.excluded;
          originalName = ts.meta.originalName;
          excludedFrom = ts.meta.excludedFrom;
          includes = ts.includes;
        };
        expected = {
          name = "~drop";
          excluded = true;
          originalName = "drop";
          excludedFrom = "parent";
          includes = [ ];
        };
      }
    );

  };
}
