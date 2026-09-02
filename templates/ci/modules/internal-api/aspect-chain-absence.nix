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

  };
}
