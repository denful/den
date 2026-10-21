{ denTest, lib, ... }:
{
  flake.tests.performance.forward = {

    test-forward-into-funny = denTest (
      { den, funnyNames, ... }:
      let
        fwd = den.provides.forward {
          each = lib.singleton true;
          fromClass = _: "src";
          intoClass = _: "funny";
          intoPath = _: [ ];
          fromAspect =
            _:
            { class, aspect-chain }:
            {
              src.names = [ "forwarded" ];
            };
        };
      in
      {
        den.aspects.test = {
          funny.names = [ "direct" ];
          includes = [ fwd ];
        };

        expr = funnyNames den.aspects.test;
        expected = [
          "direct"
          "forwarded"
        ];
      }
    );

    test-forward-many-items = denTest (
      { den, funnyNames, ... }:
      let
        items = lib.genList (i: "item${toString i}") 20;
        fwd = den.provides.forward {
          each = items;
          fromClass = _: "src";
          intoClass = _: "target";
          intoPath = _: [ "somewhere" ];
          fromAspect =
            item:
            { class, aspect-chain }:
            {
              src.names = [ item ];
            };
        };
      in
      {
        den.aspects.test = {
          funny.names = [ "root" ];
          includes = [ fwd ];
        };

        expr = funnyNames den.aspects.test;
        expected = [ "root" ];
      }
    );

  };
}
