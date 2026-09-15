# `meta.aspect-chain` must distinguish "no chain" (unknown/absent) from
# "chain is empty" (a root). Before this, both defaulted to [ ] and were
# indistinguishable, so an inline includes literal silently read as a root.
{ denTest, ... }:
{
  flake.tests.aspect-chain-absence = {

    test-root-chain-is-empty-list = denTest (
      { den, ... }:
      {
        den.aspects.foo.nixos = { };

        expr = den.aspects.foo.meta.aspect-chain;
        expected = [ ];
      }
    );

    test-inline-include-chain-is-null = denTest (
      { den, ... }:
      {
        den.aspects.igloo.includes = [
          {
            name = "tools";
            nixos = { };
          }
        ];

        expr = (builtins.head den.aspects.igloo.includes).meta.aspect-chain;
        expected = null;
      }
    );

    # A bare parametric fn (no lib/config/options args) at a nested `provides`
    # key returns a raw wrapper built directly in types.nix, bypassing the
    # module system's option merging for `meta`. That wrapper must still carry
    # its parent's provider prefix so identity.key gives it a scoped identity
    # ("foo/bar") rather than colliding with every other aspect named "bar" —
    # the gate dedups on this string.
    test-parametric-fn-provides-inherits-provider-prefix = denTest (
      { den, ... }:
      {
        den.aspects.foo.provides.bar = { host, ... }: { };

        expr = den.lib.aspects.fx.identity.key den.aspects.foo.provides.bar;
        expected = "foo/bar";
      }
    );

  };
}
