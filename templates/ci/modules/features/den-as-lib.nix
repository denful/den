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

    test-module-has-empty-stages =
      let
        ev = lib.evalModules { modules = [ denModule ]; };
        expr = lib.attrNames ev.config.den.stages;
        expected = [ ];
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

        module =
          { den, lib, ... }:
          {
            den.stages.foo.provides.foo =
              { name }:
              {
                my.names = [ "foo ${name}" ];
              };
            den.policies.foo-to-bar = {
              from = "foo";
              to = "bar";
              _core = true;
              resolve = ctx: if ctx ? name then lib.singleton { shout = lib.toUpper ctx.name; } else [ ];
            };
            den.stages.foo.provides.bar =
              { name }:
              { shout }:
              {
                my.names = [ "foo ${name} shouted ${shout}" ];
              };

            den.stages.bar.provides.bar =
              { shout }:
              {
                my.names = [ "bar ${shout}" ];
              };

            den.aspects.foobar.includes = [
              # resolveStage results carry __scopeHandlers which are
              # destroyed by providerType merge. Wrap in a function
              # so it's called at resolution time, not definition time.
              ({ class, ... }: den.lib.resolveStage "foo" { name = "good"; })
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
          "foo good shouted GOOD"
          "bar GOOD"
          "foo good"
        ];
      in
      {
        inherit expr expected;
      };

  };
}
