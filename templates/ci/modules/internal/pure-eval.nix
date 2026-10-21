{
  denTest,
  inputs,
  lib,
  ...
}:
let
  denModule = (import inputs.den.outPath).nixModule inputs;

  evalPure =
    module:
    lib.evalModules {
      modules = [
        denModule
        module
      ];
    };
in
{
  flake.tests.performance.pure = {

    test-pure-aspects-50 =
      let
        ev = evalPure (
          { den, ... }:
          {
            den.aspects = lib.genAttrs (lib.genList (i: "a${toString i}") 50) (
              name:
              den.lib.parametric {
                my.val = [ name ];
              }
            );
          }
        );
        expr = builtins.length (builtins.attrNames ev.config.den.aspects);
        expected = 50;
      in
      {
        inherit expr expected;
      };

    test-pure-ctx-chain =
      let
        aIncludes = [
          (
            { v }:
            {
              my.val = [ v ];
            }
          )
        ];
        ev = evalPure (
          { den, ... }:
          {
            den.policies.a-to-b =
              {
                __entityKind ? null,
                ...
              }@ctx:
              let
                inherit (den.lib.policy) resolve include;
              in
              if __entityKind != "a" then
                [ ]
              else if ctx ? v then
                [
                  (resolve.to "b" { v = "${ctx.v}!"; })
                  (include (
                    { v }:
                    {
                      my.val = [ v ];
                    }
                  ))
                ]
              else
                [ ];
          }
        );
        entity = ev.config.den.lib.resolveEntity "a" { v = "x"; };
        asp = entity // {
          includes = entity.includes ++ [ ev.config.den.policies.a-to-b ] ++ aIncludes;
        };
        mod = ev.config.den.lib.aspects.resolve "my" asp;
        ev2 = lib.evalModules {
          modules = [
            mod
            { options.val = lib.mkOption { type = lib.types.listOf lib.types.str; }; }
          ];
        };
        expr = lib.sort (a: b: a < b) ev2.config.val;
        expected = [
          "x"
          "x!"
        ];
      in
      {
        inherit expr expected;
      };

    test-pure-resolve-100 =
      let
        ev = evalPure (
          { den, ... }:
          {
            den.aspects.root = {
              my.val = [ "root" ];
              includes = lib.genList (i: { my.val = [ "i${toString i}" ]; }) 100;
            };
          }
        );
        mod = ev.config.den.lib.aspects.resolve "my" ev.config.den.aspects.root;
        ev2 = lib.evalModules {
          modules = [
            mod
            { options.val = lib.mkOption { type = lib.types.listOf lib.types.str; }; }
          ];
        };
        expr = builtins.length ev2.config.val;
        expected = 101;
      in
      {
        inherit expr expected;
      };

    test-pure-statics =
      let
        ev = evalPure (
          { den, ... }:
          {
            den.aspects.base = den.lib.parametric {
              my.val = [ "base" ];
              includes = [
                (
                  { class, ... }:
                  {
                    my.val = [ "static-${class}" ];
                  }
                )
              ];
            };
          }
        );
        mod = ev.config.den.lib.aspects.resolve "my" ev.config.den.aspects.base;
        ev2 = lib.evalModules {
          modules = [
            mod
            { options.val = lib.mkOption { type = lib.types.listOf lib.types.str; }; }
          ];
        };
        expr = lib.sort (a: b: a < b) ev2.config.val;
        expected = [
          "base"
          "static-my"
        ];
      in
      {
        inherit expr expected;
      };

  };
}
