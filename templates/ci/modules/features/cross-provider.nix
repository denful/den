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
        den.stages.parent.provides.parent =
          { x }:
          {
            funny.names = [ "parent-${x}" ];
          };
        den.stages.parent.provides.child =
          _:
          { x, y }:
          {
            funny.names = [ "parent-for-child-${x}-${y}" ];
          };
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
        };
        den.default.policies = [ "test-parent-to-child" ];

        den.stages.child.provides.child =
          { x, y }:
          {
            funny.names = [ "child-${y}" ];
          };

        expr = funnyNames (den.lib.resolveStage "parent" { x = "hello"; });
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
        den.stages.src.provides.src =
          { x }:
          {
            funny.names = [ x ];
          };
        den.stages.src.provides.dst =
          _:
          { x, i }:
          {
            funny.names = [ "src-for-${x}-${toString i}" ];
          };
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
        };
        den.default.policies = [ "test-src-to-dst" ];

        den.stages.dst.provides.dst =
          { x, i }:
          {
            funny.names = [ "dst-${toString i}" ];
          };

        expr = funnyNames (den.lib.resolveStage "src" { x = "a"; });
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
        den.stages.src.provides.src =
          { x }:
          {
            funny.names = [ x ];
          };
        den.policies.test-src-to-dst-no-cross = {
          from = "src";
          to = "dst";
          resolve = ctx: if !(ctx ? x) then [ ] else [ { y = ctx.x; } ];
        };
        den.default.policies = [ "test-src-to-dst-no-cross" ];

        den.stages.dst.provides.dst =
          { y }:
          {
            funny.names = [ "dst-${y}" ];
          };

        expr = funnyNames (den.lib.resolveStage "src" { x = "val"; });
        expected = [
          "dst-val"
          "val"
        ];
      }
    );

  };
}
