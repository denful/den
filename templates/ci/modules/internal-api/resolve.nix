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
            funny.names = [ "n${toString i}" ];
            includes = [ (go (i + 1)) ];
          };
    in
    go 0;

  mkWide = n: {
    funny.names = [ "root" ];
    includes = lib.genList (i: { funny.names = [ "b${toString i}" ]; }) n;
  };

  mkDeepWide =
    depth: width:
    let
      go =
        d:
        if d >= depth then
          {
            funny.names = [ "leaf" ];
            includes = lib.genList (i: { funny.names = [ "w${toString i}" ]; }) width;
          }
        else
          {
            funny.names = [ "d${toString d}" ];
            includes = [ (go (d + 1)) ];
          };
    in
    go 0;

  mkDiamond = n: {
    funny.names = [ "top" ];
    includes =
      let
        shared = {
          funny.names = [ "shared" ];
        };
      in
      lib.genList (_: {
        funny.names = [ "mid" ];
        includes = [ shared ];
      }) n;
  };
in
{
  flake.tests.performance.resolve = {

    test-chain-100 = denTest (
      { den, funnyNames, ... }:
      {
        den.aspects.deep = mkChain 100;
        expr = builtins.length (funnyNames den.aspects.deep);
        expected = 101;
      }
    );

    test-wide-200 = denTest (
      { den, funnyNames, ... }:
      {
        den.aspects.wide = mkWide 200;
        expr = builtins.length (funnyNames den.aspects.wide);
        expected = 201;
      }
    );

    test-deep-wide-20x20 = denTest (
      { den, funnyNames, ... }:
      {
        den.aspects.dw = mkDeepWide 20 20;
        expr = builtins.length (funnyNames den.aspects.dw);
        expected = 41;
      }
    );

    test-diamond-50 = denTest (
      { den, funnyNames, ... }:
      {
        den.aspects.dia = mkDiamond 50;
        expr = builtins.length (funnyNames den.aspects.dia);
        expected = 101;
      }
    );

  };
}
