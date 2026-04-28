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
                { host, ... }:
                {
                  funny.names = [ "i${toString i}-${host}" ];
                }
              )
            ];
          };
        aspects = lib.genList mkParam 30;
      in
      {
        den.schema.start.includes = [
          (
            { host }:
            {
              funny.names = [ host ];
            }
          )
        ]
        ++ aspects;

        expr = builtins.length (funnyNames (den.lib.resolveEntity "start" { host = "h"; }));
        expected = 61;
      }
    );

    test-expands-propagation = denTest (
      { den, funnyNames, ... }:
      let
        inner =
          { host, planet, ... }:
          {
            funny.names = [ "${host}-${planet}" ];
          };
        expanded = den.lib.parametric.expands { planet = "mars"; } {
          funny.names = [ "exp" ];
          includes = lib.genList (_: inner) 15;
        };
      in
      {
        den.schema.start.includes = [
          (
            { host }:
            {
              funny.names = [ host ];
            }
          )
          expanded
        ];

        expr = builtins.length (funnyNames (den.lib.resolveEntity "start" { host = "h"; }));
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
              { host, ... }:
              {
                funny.names = [ "inner-${host}" ];
              }
            )
          ];
        };
      in
      {
        den.schema.a.includes = [
          (
            { host }:
            {
              funny.names = [ "a-${host}" ];
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
          if __entityKind != "a" || !(ctx ? host) then
            [ ]
          else
            [
              (resolve.to "b" { host = "${ctx.host}!"; })
              (include (
                { host }:
                {
                  funny.names = [ "b-${host}" ];
                }
              ))
              (include shared)
            ];
        expr = builtins.length (funnyNames (den.lib.resolveEntity "a" { host = "v"; }));
        expected = 6;
      }
    );

  };
}
