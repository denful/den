# This test verifies that aspects do not use lib.functionTo merging semantics on aspect.__functor.
# See: https://github.com/vic/den/issues/216 and https://github.com/vic/flake-aspects/pull/38
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
      fooAspect = ev.config.den.lib.resolveEntity "foo" {
        x = 0;
        y = 1;
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
          {
            den.stages.foo.provides.foo = { x, y }@ctx: parametric.fixedTo ctx den.aspects.foo;
          }
        ];
      }
    );

  };
}
