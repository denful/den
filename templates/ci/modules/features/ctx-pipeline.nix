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
          den.stages.${name}.provides.${name} =
            { x }:
            {
              funny.names = [ "${name}-${x}" ];
            };
        };
        withPolicy =
          if i + 1 < n then
            {
              den.policies."${name}-to-${next}" = {
                from = name;
                to = next;
                resolve = ctx: if ctx ? x then [ { x = "${ctx.x}+${toString i}"; } ] else [ ];
              };
            }
          else
            { };
      in
      { den, ... }:
      lib.recursiveUpdate baseStage withPolicy
    ) n;

  mkFanOut =
    n:
    { den, ... }:
    {
      den.stages.root.provides.root =
        { x }:
        {
          funny.names = [ "root-${x}" ];
        };
      den.policies.root-to-leaf = {
        from = "root";
        to = "leaf";
        resolve = ctx: if ctx ? x then lib.genList (i: { x = "${ctx.x}-${toString i}"; }) n else [ ];
      };
      den.stages.leaf.provides.leaf =
        { x }:
        {
          funny.names = [ "leaf-${x}" ];
        };
    };

  mkCrossProviders =
    n:
    let
      targetNames = lib.genList (i: "t${toString i}") n;
      srcMod =
        { den, ... }:
        {
          den.stages.src.provides = {
            src =
              { v }:
              {
                funny.names = [ "src-${v}" ];
              };
          }
          // lib.listToAttrs (
            map (tgt: {
              name = tgt;
              value =
                _:
                { v }:
                {
                  funny.names = [ "cross-${tgt}-${v}" ];
                };
            }) targetNames
          );
          den.policies = lib.listToAttrs (
            map (tgt: {
              name = "src-to-${tgt}";
              value = {
                from = "src";
                to = tgt;
                resolve = ctx: if ctx ? v then [ { v = "${ctx.v}!"; } ] else [ ];
              };
            }) targetNames
          );
        };
      targetMods = lib.genList (
        i:
        let
          name = "t${toString i}";
        in
        { den, ... }:
        {
          den.stages.${name}.provides.${name} =
            { v }:
            {
              funny.names = [ "${name}-${v}" ];
            };
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
        den.default.policies = lib.genList (i: "c${toString i}-to-c${toString (i + 1)}") 29;
        expr = builtins.length (funnyNames (den.lib.resolveStage "c0" { x = "v"; }));
        expected = 30;
      }
    );

    test-fan-out-50 = denTest (
      { den, funnyNames, ... }:
      {
        imports = [ (mkFanOut 50) ];
        den.default.policies = [ "root-to-leaf" ];
        expr = builtins.length (funnyNames (den.lib.resolveStage "root" { x = "v"; }));
        expected = 51;
      }
    );

    test-cross-providers-20 = denTest (
      { den, funnyNames, ... }:
      {
        imports = mkCrossProviders 20;
        den.default.policies = lib.genList (i: "src-to-t${toString i}") 20;
        expr = builtins.length (funnyNames (den.lib.resolveStage "src" { v = "z"; }));
        expected = 41;
      }
    );

  };
}
