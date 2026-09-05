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

  };
}
