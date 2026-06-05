# This test verifies that aspects do not use lib.functionTo merging semantics on aspect.__functor.
# See: https://github.com/denful/den/issues/216 and https://github.com/vic/flake-aspects/pull/38
{
  lib,
  inputs,
  ...
}:
let

  denModule = (import inputs.den).nixModule inputs;
  testBogus =
    bogusModule:
    let
      ev = lib.evalModules {
        modules = [
          denModule
          bogusModule
        ];
      };
      entity = ev.config.den.lib.resolveEntity "foo" {
        x = 0;
        y = 1;
      };
      # Inject entity-level includes that previously came from den.entityIncludes/schema
      fooAspect = entity // {
        includes = entity.includes ++ [
          ({ x, y }@ctx: ev.config.den.lib.parametric.fixedTo ctx ev.config.den.aspects.foo)
        ];
      };
      resolve = ev.config.den.lib.aspects.resolve;
      fooModule = resolve "foo" fooAspect;

      namesModule.options.names = lib.mkOption { type = lib.types.listOf lib.types.str; };
      ev2 = lib.evalModules {
        modules = [
          fooModule
          namesModule
        ];
      };

      expr = ev2.config.names;
      expected = [
        "foo"
        "bar"
      ];
    in
    {
      inherit expr expected;
    };

in
{
  flake.tests.deadbugs-216-no-dup-functors = {
    test-no-merging-for-functors = testBogus (
      { den, ... }:
      let
        inherit (den.lib) parametric;
      in
      {
        imports = [
          {
            den.aspects.groups = parametric {
              foo = {
                names = [ "foo" ];
              };
            };
          }
          {
            den.aspects.groups = parametric {
              foo = {
                names = [ "bar" ];
              };
            };
          }
          {
            den.aspects.foo = parametric { };
          }
          {
            den.aspects.foo.includes = [ den.aspects.groups ];
          }
        ];
      }
    );

  };
}
