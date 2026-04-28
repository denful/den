{ denTest, lib, ... }:
let
  mkCtxModules =
    n:
    lib.genList (
      i:
      let
        name = "ctx-${toString i}";
        next = "ctx-${toString (i + 1)}";
        baseStage = {
          den.schema.${name}.includes = [
            (
              { x }:
              {
                funny.names = [ "${name}-${x}" ];
              }
            )
          ];
        };
      in
      { den, ... }:
      lib.recursiveUpdate baseStage (
        if i + 1 < n then
          {
            den.policies."${name}-to-${next}" =
              {
                __entityKind ? null,
                ...
              }@ctx:
              if __entityKind != name || !(ctx ? x) then
                [ ]
              else
                [ (den.lib.policy.resolve.to next { x = "${ctx.x}+${toString i}"; }) ];
          }
        else
          { }
      )
    ) n;
in
{
  flake.tests.performance.ctx-chain = {

    test-ctx-chain-5 = denTest (
      { den, funnyNames, ... }:
      {
        imports = mkCtxModules 5;
        expr = builtins.length (funnyNames (den.lib.resolveEntity "ctx-0" { x = "v"; }));
        expected = 5;
      }
    );

    test-ctx-chain-10 = denTest (
      { den, funnyNames, ... }:
      {
        imports = mkCtxModules 10;
        expr = builtins.length (funnyNames (den.lib.resolveEntity "ctx-0" { x = "v"; }));
        expected = 10;
      }
    );

    test-ctx-chain-20 = denTest (
      { den, funnyNames, ... }:
      {
        imports = mkCtxModules 20;
        expr = builtins.length (funnyNames (den.lib.resolveEntity "ctx-0" { x = "v"; }));
        expected = 20;
      }
    );

    test-ctx-fan-out-20 = denTest (
      { den, funnyNames, ... }:
      {
        imports = [
          (
            { den, ... }:
            {
              den.schema.root.includes = [
                (
                  { x }:
                  {
                    funny.names = [ "root-${x}" ];
                  }
                )
              ];
              den.schema.leaf.includes = [ ];
              den.policies.root-to-leaf =
                {
                  __entityKind ? null,
                  ...
                }@ctx:
                let
                  inherit (den.lib.policy) resolve include;
                in
                if __entityKind != "root" || !(ctx ? x) then
                  [ ]
                else
                  map (i: resolve.to "leaf" { x = "${ctx.x}-${toString i}"; }) (lib.genList (i: i) 20)
                  ++ [
                    (include (
                      { x }:
                      {
                        funny.names = [ "leaf-${x}" ];
                      }
                    ))
                  ];
            }
          )
        ];
        expr = builtins.length (funnyNames (den.lib.resolveEntity "root" { x = "v"; }));
        expected = 21;
      }
    );

  };
}
