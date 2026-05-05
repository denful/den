{ denTest, ... }:
{
  flake.tests.ctx-cross-provider = {

    test-source-provides-target = denTest (
      {
        den,
        lib,
        funnyNames,
        ...
      }:
      {
        den.schema.child.includes = [ ];
        den.policies.test-parent-to-child =
          { x, ... }:
          let
            inherit (den.lib.policy) resolve include;
          in
          [
            (resolve.to "child" { y = "derived"; })
            (include (
              { x, y }:
              {
                funny.names = [ "child-${y}" ];
              }
            ))
            (include (
              { x, y }:
              {
                funny.names = [ "parent-for-child-${x}-${y}" ];
              }
            ))
          ];
        den.schema.parent.includes = [
          (
            { x }:
            {
              funny.names = [ "parent-${x}" ];
            }
          )
          den.policies.test-parent-to-child
        ];
        expr = funnyNames (den.lib.resolveEntity "parent" { x = "hello"; });
        expected = [
          "child-derived"
          "parent-for-child-hello-derived"
          "parent-hello"
        ];
      }
    );

    test-source-provider-per-target-value = denTest (
      {
        den,
        lib,
        funnyNames,
        ...
      }:
      {
        den.schema.dst.includes = [ ];
        den.policies.test-src-to-dst =
          { x, ... }:
          let
            inherit (den.lib.policy) resolve include;
          in
          [
            (resolve.to "dst" { i = 1; })
            (resolve.to "dst" { i = 2; })
            (include (
              { x, i }:
              {
                funny.names = [ "dst-${toString i}" ];
              }
            ))
            (include (
              { x, i }:
              {
                funny.names = [ "src-for-${x}-${toString i}" ];
              }
            ))
          ];
        den.schema.src.includes = [
          (
            { x }:
            {
              funny.names = [ x ];
            }
          )
          den.policies.test-src-to-dst
        ];
        expr = funnyNames (den.lib.resolveEntity "src" { x = "a"; });
        expected = [
          "a"
          "dst-1"
          "dst-2"
          "src-for-a-1"
          "src-for-a-2"
        ];
      }
    );

    test-no-cross-provider-when-absent = denTest (
      {
        den,
        lib,
        funnyNames,
        ...
      }:
      {
        den.schema.dst.includes = [ ];
        den.policies.test-src-to-dst-no-cross =
          { x, ... }:
          let
            inherit (den.lib.policy) resolve include;
          in
          [
            (resolve.to "dst" { y = x; })
            (include (
              { y }:
              {
                funny.names = [ "dst-${y}" ];
              }
            ))
          ];
        den.schema.src.includes = [
          (
            { x }:
            {
              funny.names = [ x ];
            }
          )
          den.policies.test-src-to-dst-no-cross
        ];
        expr = funnyNames (den.lib.resolveEntity "src" { x = "val"; });
        expected = [
          "dst-val"
          "val"
        ];
      }
    );

  };
}
