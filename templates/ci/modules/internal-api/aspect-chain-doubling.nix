# `meta.aspect-chain` is a node's position, not an accumulating set. Two files
# defining one aspect path each inject the same chain, and a `listOf` type
# concatenated them into ["a" "a"] — which every descendant then inherited as
# its own prefix, corrupting the whole subtree's identities.
{ denTest, ... }:
{
  flake.tests.aspect-chain-doubling = {

    test-agreeing-definitions-collapse = denTest (
      { den, ... }:
      {
        imports = [
          { den.aspects.igloo.provides.shared = den.aspects.a.tools; }
          { den.aspects.igloo.provides.shared = den.aspects.a.tools; }
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.a.tools.nixos.environment.etc."t".text = "y";

        expr = den.aspects.igloo.provides.shared.meta.aspect-chain or [ ];
        expected = [ "a" ];
      }
    );

    # CONTROL: a single definition was never affected, so a passing multi-def
    # case above is only meaningful next to this.
    test-control-single-definition = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.a.tools.nixos.environment.etc."t".text = "y";
        den.aspects.igloo.provides.shared = den.aspects.a.tools;

        expr = den.aspects.igloo.provides.shared.meta.aspect-chain or [ ];
        expected = [ "a" ];
      }
    );

    # Container roots other than den.aspects declare their own `origin` seed
    # (batteries.nix, namespace-types.nix) rather than inheriting the [ ]
    # default. This pins those two seeds directly rather than relying on
    # suite totals, so a regression here is caught even though no other
    # cell in the corpus asserts a battery or namespace chain literal.
    test-battery-root-chain = denTest (
      { den, ... }:
      {
        expr = den.batteries.hostname.meta.aspect-chain or [ ];
        expected = [
          "den"
          "batteries"
        ];
      }
    );

    test-namespace-root-chain = denTest (
      {
        inputs,
        ns,
        ...
      }:
      {
        imports = [ (inputs.den.namespace "ns" false) ];
        ns.probe.nixos.environment.etc."t".text = "y";

        expr = ns.probe.meta.aspect-chain or [ ];
        expected = [ "ns" ];
      }
    );

  };
}
