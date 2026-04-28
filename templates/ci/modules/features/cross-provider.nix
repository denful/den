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
        den.schema.parent.includes = [
          (
            { x }:
            {
              funny.names = [ "parent-${x}" ];
            }
          )
        ];
        den.schema.child.includes = [ ];
        den.policies.test-parent-to-child = {
          to = "child";
          __functor =
            _:
            {
              __entityKind ? null,
              ...
            }@ctx:
            let
              inherit (den.lib.policy) resolve include;
            in
            if __entityKind != "parent" || !(ctx ? x) then
              [ ]
            else
              [
                (resolve { y = "derived"; })
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
        };
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
        den.schema.src.includes = [
          (
            { x }:
            {
              funny.names = [ x ];
            }
          )
        ];
        den.schema.dst.includes = [ ];
        den.policies.test-src-to-dst = {
          to = "dst";
          __functor =
            _:
            {
              __entityKind ? null,
              ...
            }@ctx:
            let
              inherit (den.lib.policy) resolve include;
            in
            if __entityKind != "src" || !(ctx ? x) then
              [ ]
            else
              [
                (resolve { i = 1; })
                (resolve { i = 2; })
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
        };
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
        den.schema.src.includes = [
          (
            { x }:
            {
              funny.names = [ x ];
            }
          )
        ];
        den.schema.dst.includes = [ ];
        den.policies.test-src-to-dst-no-cross = {
          to = "dst";
          __functor =
            _:
            {
              __entityKind ? null,
              ...
            }@ctx:
            let
              inherit (den.lib.policy) resolve include;
            in
            if __entityKind != "src" || !(ctx ? x) then
              [ ]
            else
              [
                (resolve { y = ctx.x; })
                (include (
                  { y }:
                  {
                    funny.names = [ "dst-${y}" ];
                  }
                ))
              ];
        };
        expr = funnyNames (den.lib.resolveEntity "src" { x = "val"; });
        expected = [
          "dst-val"
          "val"
        ];
      }
    );

  };
}
