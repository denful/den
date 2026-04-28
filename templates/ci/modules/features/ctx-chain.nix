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
            den.policies."${name}-to-${next}" = {
              from = name;
              to = next;
              __functor =
                _: ctx: if ctx ? x then [ (den.lib.policy.resolve { x = "${ctx.x}+${toString i}"; }) ] else [ ];
            };
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
        den.default.policies = lib.genList (i: "ctx-${toString i}-to-ctx-${toString (i + 1)}") 4;
        expr = builtins.length (funnyNames (den.lib.resolveEntity "ctx-0" { x = "v"; }));
        expected = 5;
      }
    );

    test-ctx-chain-10 = denTest (
      { den, funnyNames, ... }:
      {
        imports = mkCtxModules 10;
        den.default.policies = lib.genList (i: "ctx-${toString i}-to-ctx-${toString (i + 1)}") 9;
        expr = builtins.length (funnyNames (den.lib.resolveEntity "ctx-0" { x = "v"; }));
        expected = 10;
      }
    );

    test-ctx-chain-20 = denTest (
      { den, funnyNames, ... }:
      {
        imports = mkCtxModules 20;
        den.default.policies = lib.genList (i: "ctx-${toString i}-to-ctx-${toString (i + 1)}") 19;
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
              den.policies.root-to-leaf = {
                from = "root";
                to = "leaf";
                resolve = ctx: if ctx ? x then lib.genList (i: { x = "${ctx.x}-${toString i}"; }) 20 else [ ];
                aspects = [
                  (
                    { x }:
                    {
                      funny.names = [ "leaf-${x}" ];
                    }
                  )
                ];
              };
            }
          )
        ];
        den.default.policies = [ "root-to-leaf" ];
        expr = builtins.length (funnyNames (den.lib.resolveEntity "root" { x = "v"; }));
        expected = 21;
      }
    );

  };
}
