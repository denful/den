# Tests for the lib primitives: hasAspectIn, collectPathSet,
# mkEntityHasAspect. These exercise the query mechanics without any
# entity wiring — see has-aspect.nix for the entity-method tests.
{ denTest, lib, ... }:
{
  flake.tests.has-aspect-lib = {

    test-hasAspectIn-positive = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects) hasAspectIn;
      in
      {
        den.aspects.root.includes = [ den.aspects.child ];
        den.aspects.child.nixos = { };

        expr = hasAspectIn {
          tree = den.aspects.root;
          class = "nixos";
          ref = den.aspects.child;
        };
        expected = true;
      }
    );

    test-hasAspectIn-negative = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects) hasAspectIn;
      in
      {
        den.aspects.root.includes = [ den.aspects.child ];
        den.aspects.child.nixos = { };
        den.aspects.other.nixos = { };

        expr = hasAspectIn {
          tree = den.aspects.root;
          class = "nixos";
          ref = den.aspects.other;
        };
        expected = false;
      }
    );

    test-hasAspectIn-respects-tombstones = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects) hasAspectIn;
      in
      {
        den.aspects.root.includes = [
          den.aspects.keep
          den.aspects.drop
        ];
        den.aspects.root.meta.handleWith = den.lib.aspects.fx.constraints.exclude den.aspects.drop;
        den.aspects.keep.nixos = { };
        den.aspects.drop.nixos = { };

        expr = {
          keep = hasAspectIn {
            tree = den.aspects.root;
            class = "nixos";
            ref = den.aspects.keep;
          };
          drop = hasAspectIn {
            tree = den.aspects.root;
            class = "nixos";
            ref = den.aspects.drop;
          };
        };
        expected = {
          keep = true;
          drop = false;
        };
      }
    );

    test-collectPathSet-returns-keys = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects) collectPathSet;
        s = collectPathSet {
          tree = den.aspects.root;
          class = "nixos";
        };
      in
      {
        den.aspects.root.includes = [ den.aspects.foo.provides.bar ];
        den.aspects.foo.provides.bar.nixos = { };

        expr = {
          hasRoot = s ? "root";
          hasSub = s ? "foo/bar";
          hasNothing = s ? "nonexistent";
        };
        expected = {
          hasRoot = true;
          hasSub = true;
          hasNothing = false;
        };
      }
    );

    test-mkEntityHasAspect-shape = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects) mkEntityHasAspect;
        has = mkEntityHasAspect {
          tree = den.aspects.root;
          primaryClass = "nixos";
          classes = [ "nixos" ];
        };
      in
      {
        den.aspects.root.includes = [ den.aspects.child ];
        den.aspects.child.nixos = { };

        expr = {
          isAttrs = builtins.isAttrs has;
          hasForClass = has ? forClass;
          hasForAnyClass = has ? forAnyClass;
          callableBare = has den.aspects.child;
          callableForClass = has.forClass "nixos" den.aspects.child;
          callableForAnyClass = has.forAnyClass den.aspects.child;
        };
        expected = {
          isAttrs = true;
          hasForClass = true;
          hasForAnyClass = true;
          callableBare = true;
          callableForClass = true;
          callableForAnyClass = true;
        };
      }
    );

    test-mkEntityHasAspect-absent = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects) mkEntityHasAspect;
        has = mkEntityHasAspect {
          tree = den.aspects.root;
          primaryClass = "nixos";
          classes = [ "nixos" ];
        };
      in
      {
        den.aspects.root.nixos = { };
        den.aspects.unrelated.nixos = { };

        expr = has den.aspects.unrelated;
        expected = false;
      }
    );

    test-mkEntityHasAspect-forClass-unknown-class = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects) mkEntityHasAspect;
        has = mkEntityHasAspect {
          tree = den.aspects.root;
          primaryClass = "nixos";
          classes = [ "nixos" ];
        };
      in
      {
        den.aspects.root.includes = [ den.aspects.child ];
        den.aspects.child.nixos = { };

        # Unknown class returns false silently, not an error.
        expr = has.forClass "bogus-class" den.aspects.child;
        expected = false;
      }
    );

    test-refKey-validator-throws-on-string = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects) hasAspectIn;
        result = builtins.tryEval (hasAspectIn {
          tree = den.aspects.root;
          class = "nixos";
          ref = "not-an-aspect";
        });
      in
      {
        den.aspects.root.nixos = { };

        # tryEval returns { success = false; value = false; } on throw
        expr = result.success;
        expected = false;
      }
    );

    test-refKey-validator-throws-on-bare-meta = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects) hasAspectIn;
        result = builtins.tryEval (hasAspectIn {
          tree = den.aspects.root;
          class = "nixos";
          # missing `name` — must throw
          ref = {
            meta.provider = [ "x" ];
          };
        });
      in
      {
        den.aspects.root.nixos = { };

        expr = result.success;
        expected = false;
      }
    );

    # Factory-function aspects (`den.aspects.myFactory = arg: {...}`)
    # are merged through providerFnType and aspectSubmodule into an
    # attrset-with-__functor. The factory itself has a stable
    # aspectPath derived from its declaration name, so querying
    # `host.hasAspect den.aspects.myFactory` is well-defined.
    test-factory-fn-aspect-identity = denTest (
      { den, lib, ... }:
      {
        den.aspects.myFactory = arg: {
          nixos.environment.variables.FACTORY_ARG = arg;
        };
        # Reference the factory so submodule merging runs.
        den.aspects.consumer.includes = [ (den.aspects.myFactory "/x") ];

        expr = {
          factoryPath = den.lib.aspects.fx.identity.aspectPath den.aspects.myFactory;
          factoryIsFunction = builtins.isFunction den.aspects.myFactory;
        };
        expected = {
          factoryPath = [ "myFactory" ];
          factoryIsFunction = false;
        };
      }
    );

  };
}
