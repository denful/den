{ denTest, lib, ... }:
let
  mkChain =
    n:
    let
      go =
        i:
        if i >= n then
          { funny.names = [ "leaf" ]; }
        else
          {
            funny.names = [ "level-${toString i}" ];
            includes = [ (go (i + 1)) ];
          };
    in
    go 0;

  mkWide = n: {
    funny.names = [ "root" ];
    includes = lib.genList (i: { funny.names = [ "branch-${toString i}" ]; }) n;
  };

  mkDeepWide =
    depth: width:
    let
      go =
        d:
        if d >= depth then
          {
            funny.names = [ "leaf-d${toString d}" ];
            includes = lib.genList (i: { funny.names = [ "wide-d${toString d}-${toString i}" ]; }) width;
          }
        else
          {
            funny.names = [ "level-${toString d}" ];
            includes = [ (go (d + 1)) ];
          };
    in
    go 0;
in
{
  flake.tests.performance.depth = {

    test-deep-10 = denTest (
      { den, funnyNames, ... }:
      {
        den.aspects.deep = mkChain 10;
        expr = builtins.length (funnyNames den.aspects.deep);
        expected = 11;
      }
    );

    test-deep-50 = denTest (
      { den, funnyNames, ... }:
      {
        den.aspects.deep = mkChain 50;
        expr = builtins.length (funnyNames den.aspects.deep);
        expected = 51;
      }
    );

    test-wide-50 = denTest (
      { den, funnyNames, ... }:
      {
        den.aspects.wide = mkWide 50;
        expr = builtins.length (funnyNames den.aspects.wide);
        expected = 51;
      }
    );

    test-wide-100 = denTest (
      { den, funnyNames, ... }:
      {
        den.aspects.wide = mkWide 100;
        expr = builtins.length (funnyNames den.aspects.wide);
        expected = 101;
      }
    );

    test-deep-wide-10x10 = denTest (
      { den, funnyNames, ... }:
      {
        den.aspects.dw = mkDeepWide 10 10;
        expr = builtins.length (funnyNames den.aspects.dw);
        expected = 21;
      }
    );

  };
}
