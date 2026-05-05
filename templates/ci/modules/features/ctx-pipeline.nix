{ denTest, lib, ... }:
let
  mkCtxChain =
    n:
    lib.genList (
      i:
      let
        name = "c${toString i}";
        next = "c${toString (i + 1)}";
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
              { x, ... }: [ (den.lib.policy.resolve.to next { x = "${x}+${toString i}"; }) ];
            den.schema.${name}.includes = baseStage.den.schema.${name}.includes ++ [
              den.policies."${name}-to-${next}"
            ];
          }
        else
          { }
      )
    ) n;

  mkFanOut =
    n:
    { den, ... }:
    {
      den.schema.leaf.includes = [ ];
      den.policies.root-to-leaf =
        { x, ... }:
        let
          inherit (den.lib.policy) resolve include;
        in
        map (i: resolve.to "leaf" { x = "${x}-${toString i}"; }) (lib.genList (i: i) n)
        ++ [
          (include (
            { x }:
            {
              funny.names = [ "leaf-${x}" ];
            }
          ))
        ];
      den.schema.root.includes = [
        den.policies.root-to-leaf
        (
          { x }:
          {
            funny.names = [ "root-${x}" ];
          }
        )
      ];
    };

  mkCrossProviders =
    n:
    let
      targetNames = lib.genList (i: "t${toString i}") n;
      srcMod =
        { den, ... }:
        {
          den.policies = lib.listToAttrs (
            map (tgt: {
              name = "src-to-${tgt}";
              value =
                { v, ... }:
                let
                  inherit (den.lib.policy) resolve include;
                in
                [
                  (resolve.to tgt { v = "${v}!"; })
                  (include (
                    { v }:
                    {
                      funny.names = [ "${tgt}-${v}" ];
                    }
                  ))
                  (include (
                    { v }:
                    {
                      funny.names = [ "cross-${tgt}-${v}" ];
                    }
                  ))
                ];
            }) targetNames
          );
          den.schema.src.includes = [
            (
              { v }:
              {
                funny.names = [ "src-${v}" ];
              }
            )
          ]
          ++ map (tgt: den.policies."src-to-${tgt}") targetNames;
        };
      targetMods = lib.genList (
        i:
        let
          name = "t${toString i}";
        in
        { den, ... }:
        {
          den.schema.${name}.includes = [ ];
        }
      ) n;
    in
    [ srcMod ] ++ targetMods;

in
{
  flake.tests.performance.ctx = {

    test-chain-30 = denTest (
      { den, funnyNames, ... }:
      {
        imports = mkCtxChain 30;
        expr = builtins.length (funnyNames (den.lib.resolveEntity "c0" { x = "v"; }));
        expected = 30;
      }
    );

    test-fan-out-50 = denTest (
      { den, funnyNames, ... }:
      {
        imports = [ (mkFanOut 50) ];
        expr = builtins.length (funnyNames (den.lib.resolveEntity "root" { x = "v"; }));
        expected = 51;
      }
    );

    test-cross-providers-20 = denTest (
      { den, funnyNames, ... }:
      {
        imports = mkCrossProviders 20;
        expr = builtins.length (funnyNames (den.lib.resolveEntity "src" { v = "z"; }));
        expected = 41;
      }
    );

  };
}
