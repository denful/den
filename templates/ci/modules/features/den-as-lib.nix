{
  inputs,
  lib,
  config,
  ...
}:
let
  denPath = inputs.den.outPath;
  denModule = (import denPath).nixModule inputs;
in
{
  flake.tests.den-as-lib = {

    test-expose-lib-functions =
      let
        den-lib = import denPath { inherit lib config inputs; };
        expr = den-lib.canTake.exactly { x = 1; } ({ x, y }: { });
        expected = false;
      in
      {
        inherit expr expected;
      };

    test-module-usable-in-any-module-system =
      let
        ev = lib.evalModules { modules = [ denModule ]; };
        expr = ev.config.den ? lib.parametric;
        expected = true;
      in
      {
        inherit expr expected;
      };

    test-module-has-empty-aspects =
      let
        ev = lib.evalModules { modules = [ denModule ]; };
        expr = lib.attrNames ev.config.den.aspects;
        expected = [ ];
      in
      {
        inherit expr expected;
      };

    test-module-has-no-nixos-domain =
      let
        names = [
          "hosts"
          "homes"
          "schema"
          "default"
          "provides"
          "ful"
        ];
        ev = lib.evalModules { modules = [ denModule ]; };
        expr = builtins.all (name: !ev.config.den ? ${name}) names;
        expected = true;
      in
      {
        inherit expr expected;
      };

    test-module-can-resolve-custom-domain =
      let
        ev = lib.evalModules {
          modules = [
            denModule
            module
          ];
        };

        fooIncludes = [
          (
            { name }:
            {
              my.names = [ "foo ${name}" ];
            }
          )
        ];

        module =
          { den, lib, ... }:
          {
            den.policies.foo-to-bar =
              {
                __entityKind ? null,
                ...
              }@ctx:
              let
                inherit (den.lib.policy) resolve include;
              in
              if __entityKind != "foo" then
                [ ]
              else if ctx ? name then
                [
                  (resolve.to "bar" { shout = lib.toUpper ctx.name; })
                  (include (
                    { shout }:
                    {
                      my.names = [ "bar ${shout}" ];
                    }
                  ))
                ]
              else
                [ ];

            den.aspects.foobar.includes = [
              den.policies.foo-to-bar
              # resolveEntity results carry __scopeHandlers which are
              # destroyed by providerType merge. Wrap in a function
              # so it's called at resolution time, not definition time.
              (
                { class, ... }:
                let
                  entity = den.lib.resolveEntity "foo" { name = "good"; };
                in
                entity // { includes = entity.includes ++ fooIncludes; }
              )
            ];
          };

        myMod = ev.config.den.lib.aspects.resolve "my" ev.config.den.aspects.foobar;
        nameMod.options.names = lib.mkOption { type = lib.types.listOf lib.types.str; };
        ev2 = lib.evalModules {
          modules = [
            nameMod
            myMod
          ];
        };

        expr = ev2.config.names;
        expected = [
          "bar GOOD"
          "foo good"
        ];
      in
      {
        inherit expr expected;
      };

  };
}
