{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.performance.namespace = {

    test-namespace-many-aspects = denTest (
      {
        den,
        ns,
        funnyNames,
        ...
      }:
      {
        imports = [ (inputs.den.namespace "ns" false) ];
        ns = lib.genAttrs (lib.genList (i: "a${toString i}") 30) (name: {
          funny.names = [ name ];
        });
        den.aspects.root = {
          funny.names = [ "root" ];
          includes = lib.genList (i: ns."a${toString i}") 30;
        };

        expr = builtins.length (funnyNames den.aspects.root);
        expected = 31;
      }
    );

    test-namespace-merged-sources = denTest (
      {
        den,
        ns,
        funnyNames,
        ...
      }:
      let
        mkSrc = i: {
          denful.ns = lib.genAttrs (lib.genList (j: "x${toString j}") 10) (name: {
            funny.names = [ "${name}-src${toString i}" ];
          });
        };
        sources = lib.genList mkSrc 5;
      in
      {
        imports = [ (inputs.den.namespace "ns" sources) ];
        den.aspects.root = {
          funny.names = [ "root" ];
          includes = lib.genList (i: ns."x${toString i}") 10;
        };

        expr = builtins.length (funnyNames den.aspects.root);
        expected = 51;
      }
    );

    test-namespace-with-providers = denTest (
      {
        den,
        ns,
        funnyNames,
        ...
      }:
      {
        imports = [ (inputs.den.namespace "ns" false) ];
        ns.parent = {
          funny.names = [ "parent" ];
          provides = lib.genAttrs (lib.genList (i: "p${toString i}") 10) (name: {
            funny.names = [ name ];
          });
        };
        den.aspects.root = {
          funny.names = [ "root" ];
          includes = [ ns.parent ];
        };

        expr = builtins.length (funnyNames den.aspects.root);
        expected = 2;
      }
    );

  };
}
