# A let-bound aspect value included by two owners is one value, written once,
# referenced twice — not two authored aspects. The inline-chain fill (compile-
# static.nix) sees `meta.aspect-chain == null` at both inclusion sites with no
# way to tell "one value, two references" from "two separately-written
# literals", so it stamps each site with its own inclusion-site chain and the
# shared value splits into two nodes and double-emits. Because
# `environment.etc.<name>.text` is `types.lines`, the duplication reaches
# delivered content, not just a diagnostic identity string.
{ denTest, ... }:
{
  flake.tests.deadbugs.shared-raw-include-splits = {

    # The defect: one node, one emission — `text` is the cell that fails on
    # delivered content rather than on a diagnostic string. A cell asserting
    # only `count` would pass a fix that deduped the node while still
    # emitting the content twice.
    test-shared-raw-value-included-by-two-owners-is-one-node = denTest (
      { den, igloo, ... }:
      let
        shared = {
          name = "sharedraw";
          nixos.environment.etc."sharedraw".text = "yes";
        };
        nodes = builtins.filter (n: n.name == "sharedraw") den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.o1
          den.aspects.o2
        ];

        den.aspects.o1.includes = [ shared ];
        den.aspects.o2.includes = [ shared ];

        expr = {
          count = builtins.length nodes;
          identities = builtins.sort builtins.lessThan (map (n: n.identity) nodes);
          text = igloo.environment.etc."sharedraw".text;
        };
        expected = {
          count = 1;
          identities = [ "o1/sharedraw" ];
          text = "yes";
        };
      }
    );

    # Same defect, inclusion order reversed. The surviving identity string is
    # order-dependent (whichever owner is walked first claims the chain) —
    # asserted here is only the property that does NOT depend on walk order:
    # reordering must not resurrect the double emission. The identity string
    # itself is deliberately not asserted; freezing it would turn a future
    # order-independent fix into an apparent regression.
    test-shared-raw-value-reordered-owners-still-one-node = denTest (
      { den, igloo, ... }:
      let
        sharedRev = {
          name = "sharedrev";
          nixos.environment.etc."sharedrev".text = "yes";
        };
        nodes = builtins.filter (n: n.name == "sharedrev") den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.r2
          den.aspects.r1
        ];

        den.aspects.r1.includes = [ sharedRev ];
        den.aspects.r2.includes = [ sharedRev ];

        expr = {
          count = builtins.length nodes;
          text = igloo.environment.etc."sharedrev".text;
        };
        expected = {
          count = 1;
          text = "yes";
        };
      }
    );

    # CONTROL: a declared aspect (chain already `[ ]`, never null) referenced
    # by two owners must keep its one identity, unaffected by any of this.
    # Already green before this fix; its job is to stay green — it falsifies
    # a fix that stamps the inclusion site onto every node rather than only
    # where the chain is absent.
    test-control-declared-shared-aspect-keeps-one-identity = denTest (
      { den, igloo, ... }:
      let
        nodes = builtins.filter (n: n.name == "shared") den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.o3a
          den.aspects.o3b
        ];

        den.aspects.o3a.includes = [ den.aspects.shared ];
        den.aspects.o3b.includes = [ den.aspects.shared ];

        den.aspects.shared.nixos.environment.etc."shared".text = "yes";

        expr = {
          count = builtins.length nodes;
          identities = builtins.sort builtins.lessThan (map (n: n.identity) nodes);
          text = igloo.environment.etc."shared".text;
        };
        expected = {
          count = 1;
          identities = [ "shared" ];
          text = "yes";
        };
      }
    );

    # O2: a factory called twice reports ONE __defPos (the call site inside
    # the factory body never changes) but TWO distinct raw values — the
    # rejected `38e1f725` mechanism keyed the registry on that position alone
    # and merged them, silently dropping beta's delivery. The value-equality
    # guard must see the two calls differ and let both through.
    test-factory-samename-two-owners = denTest (
      { den, igloo, ... }:
      let
        mkTool = tag: {
          name = "tools";
          nixos.environment.etc.${tag}.text = "yes";
        };
        toolsNodes = builtins.filter (n: n.name == "tools") den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.alpha
          den.aspects.beta
        ];

        den.aspects.alpha.includes = [ (mkTool "alphafile") ];
        den.aspects.beta.includes = [ (mkTool "betafile") ];

        expr = {
          alpha = igloo.environment.etc ? "alphafile";
          beta = igloo.environment.etc ? "betafile";
          count = builtins.length toolsNodes;
          identities = builtins.sort builtins.lessThan (map (n: n.identity) toolsNodes);
        };
        expected = {
          alpha = true;
          beta = true;
          count = 2;
          identities = [
            "alpha/tools"
            "beta/tools"
          ];
        };
      }
    );

    # O3: same class of defect as O2, reached via `base // { ... }` instead of
    # a factory call — each specialisation is a distinct raw value at one
    # position.
    test-overlay-samename-two-owners = denTest (
      { den, igloo, ... }:
      let
        base = {
          name = "tools";
          nixos.environment.etc."common".text = "yes";
        };
        toolsNodes = builtins.filter (n: n.name == "tools") den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.alpha
          den.aspects.beta
        ];

        den.aspects.alpha.includes = [
          (base // { nixos.environment.etc."alphaonly".text = "yes"; })
        ];
        den.aspects.beta.includes = [
          (base // { nixos.environment.etc."betaonly".text = "yes"; })
        ];

        expr = {
          alpha = igloo.environment.etc ? "alphaonly";
          beta = igloo.environment.etc ? "betaonly";
          count = builtins.length toolsNodes;
          identities = builtins.sort builtins.lessThan (map (n: n.identity) toolsNodes);
        };
        expected = {
          alpha = true;
          beta = true;
          count = 2;
          identities = [
            "alpha/tools"
            "beta/tools"
          ];
        };
      }
    );

    # O5: two BYTE-IDENTICAL inline literals at two source positions split
    # into two nodes, and that is accepted — they never collide in the
    # registry because they occupy two positions, so the equality guard is
    # never consulted. Asserted so a future author does not read this split
    # as a regression.
    test-byte-identical-literals = denTest (
      { den, igloo, ... }:
      let
        twinNodes = builtins.filter (n: n.name == "twin") den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.alpha
          den.aspects.beta
        ];

        den.aspects.alpha.includes = [
          {
            name = "twin";
            nixos.environment.etc."twin".text = "yes";
          }
        ];
        den.aspects.beta.includes = [
          {
            name = "twin";
            nixos.environment.etc."twin".text = "yes";
          }
        ];

        expr = {
          count = builtins.length twinNodes;
          identities = builtins.sort builtins.lessThan (map (n: n.identity) twinNodes);
          text = igloo.environment.etc."twin".text;
        };
        expected = {
          count = 2;
          identities = [
            "alpha/twin"
            "beta/twin"
          ];
          text = "yes\nyes";
        };
      }
    );

    # O6: a shared value that is itself cyclic. Two inclusion sites of one
    # let-bound cyclic value must still collapse to one node — proving the
    # equality guard's raw-value comparison takes the pointer-identical O(1)
    # path rather than descending into the cycle (a distinct cyclic value
    # would have to descend; see deadbugs/aspect-equality-author-cycle for
    # that accepted cost).
    test-shared-cyclic-value-across-two-owners-is-one-node = denTest (
      { den, igloo, ... }:
      let
        shared =
          let
            v = {
              name = "loopy";
              carrier.loop = v;
              nixos.environment.etc."loopy".text = "yes";
            };
          in
          v;
        nodes = builtins.filter (n: n.name == "loopy") den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.o1
          den.aspects.o2
        ];

        den.aspects.o1.includes = [ shared ];
        den.aspects.o2.includes = [ shared ];

        expr = {
          count = builtins.length nodes;
          text = igloo.environment.etc."loopy".text;
        };
        expected = {
          count = 1;
          text = "yes";
        };
      }
    );

  };
}
