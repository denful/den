{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-identity = {

    test-aspectPath-with-chain = denTest (
      { den, ... }:
      let
        a = {
          name = "sub";
          meta = {
            aspect-chain = [ "monitoring" ];
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

    test-aspectPath-no-chain = denTest (
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

    test-tombstone-shape = denTest (
      { den, ... }:
      let
        a = {
          name = "drop";
          meta = {
            aspect-chain = [ ];
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
