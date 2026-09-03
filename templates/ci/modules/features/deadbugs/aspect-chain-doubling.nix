# `meta.provider` is a node's position, not an accumulating set. Two files
# defining one aspect path each inject the same chain, and a `listOf` type
# concatenated them into ["a" "a"] — which every descendant then inherited as
# its own prefix, corrupting the whole subtree's identities.
{ denTest, ... }:
{
  flake.tests.deadbugs.aspect-chain-doubling = {

    test-agreeing-definitions-collapse = denTest (
      { den, ... }:
      {
        imports = [
          { den.aspects.igloo.provides.shared = den.aspects.a.tools; }
          { den.aspects.igloo.provides.shared = den.aspects.a.tools; }
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.a.tools.nixos.environment.etc."t".text = "y";

        expr = den.aspects.igloo.provides.shared.meta.provider or [ ];
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

        expr = den.aspects.igloo.provides.shared.meta.provider or [ ];
        expected = [ "a" ];
      }
    );

  };
}
