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
        den.entityIncludes.parent = [
          (
            { x }:
            {
              funny.names = [ "parent-${x}" ];
            }
          )
        ];
        den.entityIncludes.child = [ ];
        den.policies.test-parent-to-child = {
          from = "parent";
          to = "child";
          resolve =
            ctx:
            if !(ctx ? x) then
              [ ]
            else
              [
                {
                  inherit (ctx) x;
                  y = "derived";
                }
              ];
          aspects = [
            (
              { x, y }:
              {
                funny.names = [ "child-${y}" ];
              }
            )
            (
              { x, y }:
              {
                funny.names = [ "parent-for-child-${x}-${y}" ];
              }
            )
          ];
        };
        den.default.policies = [ "test-parent-to-child" ];

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
        den.entityIncludes.src = [
          (
            { x }:
            {
              funny.names = [ x ];
            }
          )
        ];
        den.entityIncludes.dst = [ ];
        den.policies.test-src-to-dst = {
          from = "src";
          to = "dst";
          resolve =
            ctx:
            if !(ctx ? x) then
              [ ]
            else
              [
                {
                  inherit (ctx) x;
                  i = 1;
                }
                {
                  inherit (ctx) x;
                  i = 2;
                }
              ];
          aspects = [
            (
              { x, i }:
              {
                funny.names = [ "dst-${toString i}" ];
              }
            )
            (
              { x, i }:
              {
                funny.names = [ "src-for-${x}-${toString i}" ];
              }
            )
          ];
        };
        den.default.policies = [ "test-src-to-dst" ];

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
        den.entityIncludes.src = [
          (
            { x }:
            {
              funny.names = [ x ];
            }
          )
        ];
        den.entityIncludes.dst = [ ];
        den.policies.test-src-to-dst-no-cross = {
          from = "src";
          to = "dst";
          resolve = ctx: if !(ctx ? x) then [ ] else [ { y = ctx.x; } ];
          aspects = [
            (
              { y }:
              {
                funny.names = [ "dst-${y}" ];
              }
            )
          ];
        };
        den.default.policies = [ "test-src-to-dst-no-cross" ];

        expr = funnyNames (den.lib.resolveEntity "src" { x = "val"; });
        expected = [
          "dst-val"
          "val"
        ];
      }
    );

  };
}
