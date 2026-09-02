# A `provides` (or `_`) key defined in more than one file merges into a content
# wrapper, which carries `__contentValues` / `__provider` / `_` beside the real
# children. Those leaked out as provides children: they surfaced as keys of the
# published `provides`, entered `__providesForwarded`, and `_` — not being
# `__`-prefixed — registered an inert cross-provide policy of its own.
#
# `__functor` IS expected in each list: root publishes provides as
# `providesChildren // { __functor = …; }` (mergeWithAspectMeta's
# syntheticProvides) and nested keys match that shape deliberately.
{ denTest, ... }:
{
  flake.tests.deadbugs.multidef-provides-internals = {

    test-multidef-underscore-hides-wrapper-internals = denTest (
      { den, ... }:
      {
        imports = [
          { den.aspects.alpha.tools._.one.nixos.environment.etc."1".text = "y"; }
          { den.aspects.alpha.tools._.two.nixos.environment.etc."2".text = "y"; }
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = builtins.attrNames (den.aspects.alpha.tools.provides or { });
        expected = [
          "__functor"
          "one"
          "two"
        ];
      }
    );

    # The same leak arrives through the `provides` spelling with no `_` involved,
    # so this is the arm proving the fix is not specific to the alias fold.
    test-multidef-provides-hides-wrapper-internals = denTest (
      { den, ... }:
      {
        imports = [
          { den.aspects.alpha.tools.provides.one.nixos.environment.etc."1".text = "y"; }
          { den.aspects.alpha.tools.provides.two.nixos.environment.etc."2".text = "y"; }
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = builtins.attrNames (den.aspects.alpha.tools.provides or { });
        expected = [
          "__functor"
          "one"
          "two"
        ];
      }
    );

    # CONTROL: the shape nested keys are being held to. A root aspect was never
    # affected, so the two arms above are only meaningful beside it.
    test-control-root-provides-shape = denTest (
      { den, ... }:
      {
        imports = [
          { den.aspects.alpha.provides.one.nixos.environment.etc."1".text = "y"; }
          { den.aspects.alpha.provides.two.nixos.environment.etc."2".text = "y"; }
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = builtins.attrNames (den.aspects.alpha.provides or { });
        expected = [
          "__functor"
          "one"
          "two"
        ];
      }
    );

  };
}
