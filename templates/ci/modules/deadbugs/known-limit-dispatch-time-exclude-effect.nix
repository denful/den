# A KNOWN LIMIT, pinned as it behaves, not as it should: a `policy.exclude`
# effect returned by a policy that another policy's `include` delivers is
# registered when that policy dispatches, after the includes it names were
# gated, so it removes nothing, at its own scope or in its includer's subtree.
# The early path (a policy listed in an aspect's includes) is covered by
# policy-exclude-reaches-includer-subtree. A fix flips the two `known-limit`
# cells deliberately; den v2's stratified rules (den-694-spec.md §0.3) are
# where it is expected to go. The sibling cells pin #613's tree position.
{ denTest, lib, ... }:
let
  base = {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.aspects.plain.nixos.environment.etc.plain.text = "x";
  };
  exPol = den: x: den.lib.policy.mkPolicy "ex" ({ host, ... }: [ (den.lib.policy.exclude x) ]);
  outer =
    den: inner: den.lib.policy.mkPolicy "outer" ({ host, ... }: [ (den.lib.policy.include inner) ]);
  got = igloo: k: igloo.environment.etc ? ${k};
  cell =
    extra: k: expected:
    denTest (
      { den, igloo, ... }:
      {
        imports = [
          base
          (extra den)
        ];
        expr = got igloo k;
        inherit expected;
      }
    );
in
{
  flake.tests.known-limit-dispatch-time-exclude-effect = {
    # Controls: no exclude lands; the list and the early effect remove it.
    test-ctl-no-exclude = cell (den: {
      den.aspects.igloo.includes = [ den.aspects.plain ];
    }) "plain" true;
    test-ctl-list = cell (den: {
      den.aspects.igloo.includes = [ den.aspects.plain ];
      den.aspects.igloo.excludes = [ den.aspects.plain ];
    }) "plain" false;
    test-ctl-early-effect = cell (den: {
      den.aspects.igloo.includes = [
        den.aspects.plain
        (exPol den den.aspects.plain)
      ];
    }) "plain" false;
    # The limit: a dispatch-time exclude effect removes nothing.
    test-known-limit-same-scope = cell (den: {
      den.aspects.igloo.includes = [
        den.aspects.plain
        (outer den (exPol den den.aspects.plain))
      ];
    }) "plain" true;
    test-known-limit-includer-subtree = cell (den: {
      den.aspects.igloo.includes = [
        (den.lib.policy.mkPolicy "outer2" (
          { host, ... }:
          [
            (den.lib.policy.include (exPol den den.aspects.plain))
            (den.lib.policy.include den.aspects.plain)
          ]
        ))
      ];
    }) "plain" true;
    # An aspect's `excludes` reaches its own subtree, not a sibling's include,
    # whether the aspect is included statically or by a dispatch-time include.
    test-tree-position-sibling-static = cell (den: {
      den.aspects.igloo.includes = [
        den.aspects.plain
        {
          name = "carrier";
          excludes = [ den.aspects.plain ];
        }
      ];
    }) "plain" true;
    test-tree-position-sibling-delivered = cell (den: {
      den.aspects.igloo.includes = [
        den.aspects.plain
        (outer den {
          name = "carrier";
          excludes = [ den.aspects.plain ];
        })
      ];
    }) "plain" true;
  };
}
