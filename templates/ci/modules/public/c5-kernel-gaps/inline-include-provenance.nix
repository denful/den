# An aspect written inline into `includes` belongs to the aspect that includes
# it, and must carry that owner's chain. Today it carries none, and a node with
# no chain answers ROOT, which is the same answer a genuine root gives: two
# owners writing `{ name = "tools"; ... }` collapse onto one identity and gate
# dedup drops one of them.
#
# Anonymous inline includes already get `<parent>/<anon>:<idx>`, so den already
# applies this rule; it just does not apply it to named values.
{ denTest, ... }:
{
  flake.tests.deadbugs.inline-include-provenance = {

    test-inline-includes-from-different-owners-both-deliver = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.alpha
          den.aspects.beta
        ];

        den.aspects.alpha.includes = [
          {
            name = "tools";
            nixos.environment.etc."alpha".text = "yes";
          }
        ];

        den.aspects.beta.includes = [
          {
            name = "tools";
            nixos.environment.etc."beta".text = "yes";
          }
        ];

        expr = {
          alpha = igloo.environment.etc ? "alpha";
          beta = igloo.environment.etc ? "beta";
        };
        expected = {
          alpha = true;
          beta = true;
        };
      }
    );

    # Delivery alone would pass for a fix that just kept the two registrations
    # apart without actually distinguishing identity (e.g. widening the gate's
    # dedup key on some unrelated field). Assert at the membership seam
    # instead: the two "tools" nodes must be genuinely distinct identities.
    test-inline-includes-from-different-owners-have-distinct-identities = denTest (
      { den, ... }:
      let
        toolsNodes = builtins.filter (n: n.name == "tools") den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.alpha
          den.aspects.beta
        ];

        den.aspects.alpha.includes = [
          {
            name = "tools";
            nixos.environment.etc."alpha".text = "yes";
          }
        ];

        den.aspects.beta.includes = [
          {
            name = "tools";
            nixos.environment.etc."beta".text = "yes";
          }
        ];

        expr = {
          count = builtins.length toolsNodes;
          identities = builtins.sort builtins.lessThan (map (n: n.identity) toolsNodes);
        };
        expected = {
          count = 2;
          identities = [
            "alpha/tools"
            "beta/tools"
          ];
        };
      }
    );

    # Two levels of unfilled inline literals: "mid" is itself an inline literal
    # nested in "outer"'s includes, and "leaf" is an inline literal nested in
    # "mid"'s includes. Both must be filled — "mid" from outer's position, then
    # "leaf" from mid's (already-filled) position — so leaf's full chain
    # reflects both ancestors, not just its immediate parent.
    test-inline-include-nested-two-levels-gets-full-chain = denTest (
      { den, igloo, ... }:
      let
        leafNodes = builtins.filter (n: n.name == "leaf") den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.outer ];

        den.aspects.outer.includes = [
          {
            name = "mid";
            includes = [
              {
                name = "leaf";
                nixos.environment.etc."leaf".text = "yes";
              }
            ];
          }
        ];

        expr = {
          delivered = igloo.environment.etc ? "leaf";
          identity = (builtins.head leafNodes).identity;
        };
        expected = {
          delivered = true;
          identity = "outer/mid/leaf";
        };
      }
    );

    # CONTROL: a declared aspect (not an inline literal — its chain is already
    # "[ ]", not null) referenced from two different owners must keep its ONE
    # identity. Falsifies any fix that stamps the inclusion site onto every
    # node instead of filling only where the chain is absent — that would give
    # this aspect two identities and double-emit it.
    test-control-shared-declared-aspect-keeps-one-identity = denTest (
      { den, igloo, ... }:
      let
        sharedNodes = builtins.filter (n: n.name == "shared") den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.owner1
          den.aspects.owner2
        ];

        den.aspects.owner1.includes = [ den.aspects.shared ];
        den.aspects.owner2.includes = [ den.aspects.shared ];

        den.aspects.shared.nixos.environment.etc."shared".text = "yes";

        expr = {
          delivered = igloo.environment.etc ? "shared";
          count = builtins.length sharedNodes;
        };
        expected = {
          delivered = true;
          count = 1;
        };
      }
    );

  };
}
