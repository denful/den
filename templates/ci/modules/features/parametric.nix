{ denTest, lib, ... }:
{
  flake.tests.performance.parametric = {

    test-fixedTo-deep-chain = denTest (
      { den, funnyNames, ... }:
      let
        leaf = den.lib.parametric {
          funny.names = [ "leaf" ];
        };
        mid = den.lib.parametric {
          funny.names = [ "mid" ];
          includes = [ leaf ];
        };
        top = den.lib.parametric.fixedTo { level = "deep"; } {
          funny.names = [ "top" ];
          includes = lib.genList (_: mid) 20;
        };
      in
      {
        den.schema.start.includes = [
          (
            { level }:
            {
              funny.names = [ level ];
            }
          )
          top
        ];

        expr = builtins.length (funnyNames (den.lib.resolveEntity "start" { level = "deep"; }));
        expected = 42;
      }
    );

    test-atLeast-wide = denTest (
      { den, funnyNames, ... }:
      let
        mkParam =
          i:
          den.lib.parametric {
            funny.names = [ "p${toString i}" ];
            includes = [
              (
                { tag, ... }:
                {
                  funny.names = [ "i${toString i}-${tag}" ];
                }
              )
            ];
          };
        aspects = lib.genList mkParam 30;
      in
      {
        den.schema.start.includes = [
          (
            { tag }:
            {
              funny.names = [ tag ];
            }
          )
        ]
        ++ aspects;

        expr = builtins.length (funnyNames (den.lib.resolveEntity "start" { tag = "h"; }));
        expected = 61;
      }
    );

    test-expands-propagation = denTest (
      { den, funnyNames, ... }:
      let
        inner =
          { tag, planet, ... }:
          {
            funny.names = [ "${tag}-${planet}" ];
          };
        expanded = den.lib.parametric.expands { planet = "mars"; } {
          funny.names = [ "exp" ];
          includes = lib.genList (_: inner) 15;
        };
      in
      {
        den.schema.start.includes = [
          (
            { tag }:
            {
              funny.names = [ tag ];
            }
          )
          expanded
        ];

        expr = builtins.length (funnyNames (den.lib.resolveEntity "start" { tag = "h"; }));
        expected = 17;
      }
    );

    test-dedup-parametric = denTest (
      { den, funnyNames, ... }:
      let
        shared = den.lib.parametric {
          funny.names = [ "shared" ];
          includes = [
            (
              { tag, ... }:
              {
                funny.names = [ "inner-${tag}" ];
              }
            )
          ];
        };
      in
      {
        den.schema.a.includes = [
          (
            { tag }:
            {
              funny.names = [ "a-${tag}" ];
            }
          )
          shared
        ];
        den.schema.b.includes = [ ];
        den.policies.a-to-b =
          {
            __entityKind ? null,
            ...
          }@ctx:
          let
            inherit (den.lib.policy) resolve include;
          in
          if __entityKind != "a" || !(ctx ? tag) then
            [ ]
          else
            [
              (resolve.to "b" { tag = "${ctx.tag}!"; })
              (include (
                { tag }:
                {
                  funny.names = [ "b-${tag}" ];
                }
              ))
              (include shared)
            ];
        expr = builtins.length (funnyNames (den.lib.resolveEntity "a" { tag = "v"; }));
        expected = 6;
      }
    );

  };
}
