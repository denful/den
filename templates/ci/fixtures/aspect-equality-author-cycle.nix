# ACCEPTED COST of the value-equality identity guard (compile-static.nix).
#
# Two DISTINCT raw aspect values at one `name =` position, where one is
# self-referential at a key interned BEFORE the first differing key, make the
# guard's `==` diverge: `error: stack overflow; max-call-depth exceeded`. Nix
# compares attributes in symbol-interning (parse) order, not alphabetical
# order, so no short-circuit argument closes this. `builtins.tryEval` does not
# catch it — the divergence itself overflows under tryEval too.
#
# Accepted because it fails LOUD, never silent: the alternative (a depth-
# bounded equality) forfeits the pointer-identity fast path and re-opens the
# silent drop this guard exists to close.
#
# The two cells are written out longhand rather than through a shared helper:
# the hole depends on the order two keys are PARSED in, so factoring them
# together silently changes what is measured (both arms overflowed the one
# time this was tried).
#
# NOT collected under `templates/ci/modules/` — measured (this session, this
# tree): `nix develop -c just ci aspect-equality-author-cycle` produced NO
# summary line (no 🎉/😢/💥) on either stream and EXIT=1: the overflowing
# nix-eval-jobs worker crashes the whole collected run rather than surfacing
# as an ordinary ❌ row, indistinguishable from a crashed CI. Collecting this
# fixture would destroy the gate every other oracle in this suite depends on.
# `import-tree ./modules` (templates/ci/flake.nix) only walks
# `templates/ci/modules`, so this file living under `templates/ci/fixtures/`
# instead (the same precedent as `templates/ci/non-dendritic/`) is never
# collected.
#
# ORACLE — both arms, one run. If they agree, the fixture has measured
# nothing:
#
#   cp templates/ci/fixtures/aspect-equality-author-cycle.nix \
#      templates/ci/modules/features/deadbugs/
#   git add templates/ci/modules/features/deadbugs/aspect-equality-author-cycle.nix
#
#   nix eval --override-input den . \
#     './templates/ci#tests.deadbugs.aspect-equality-author-cycle.test-control-difference-before-cycle.expr'
#   => { common = true; count = 2; }                     EXIT=0
#
#   nix eval --override-input den . \
#     './templates/ci#tests.deadbugs.aspect-equality-author-cycle.test-cycle-before-difference.expr'
#   => error: stack overflow; max-call-depth exceeded    EXIT=1
#
#   git rm --cached templates/ci/modules/features/deadbugs/aspect-equality-author-cycle.nix
#   rm templates/ci/modules/features/deadbugs/aspect-equality-author-cycle.nix
{ denTest, ... }:
{
  flake.tests.deadbugs.aspect-equality-author-cycle = {

    # THE HOLE: `cyc` is written before `dif`, so it is interned first and
    # compared first — everything before it is equal, so `==` descends into
    # the cycle before it ever reaches the differing key.
    test-cycle-before-difference = denTest (
      { den, igloo, ... }:
      let
        mkTool =
          tag:
          let
            v = {
              name = "tools";
              nixos.environment.etc."common".text = "yes";
              cyc.loop = v;
              dif = tag;
            };
          in
          v;
        nodes = builtins.filter (n: n.name == "tools") den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [
          den.aspects.alpha
          den.aspects.beta
        ];
        den.aspects.alpha.includes = [ (mkTool "a") ];
        den.aspects.beta.includes = [ (mkTool "b") ];

        expr = {
          count = builtins.length nodes;
          common = igloo.environment.etc ? "common";
        };
        expected = {
          count = 2;
          common = true;
        };
      }
    );

    # LIVE CONTROL: identical construction, the two keys swapped so the
    # differing key is parsed and compared first — must return a value, never
    # an error. Its presence in the same run is what makes the hole a finding
    # rather than a broken instrument.
    test-control-difference-before-cycle = denTest (
      { den, igloo, ... }:
      let
        mkTool =
          tag:
          let
            v = {
              name = "tools";
              nixos.environment.etc."common".text = "yes";
              adif = tag;
              bcyc.loop = v;
            };
          in
          v;
        nodes = builtins.filter (n: n.name == "tools") den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [
          den.aspects.alpha
          den.aspects.beta
        ];
        den.aspects.alpha.includes = [ (mkTool "a") ];
        den.aspects.beta.includes = [ (mkTool "b") ];

        expr = {
          count = builtins.length nodes;
          common = igloo.environment.etc ? "common";
        };
        expected = {
          count = 2;
          common = true;
        };
      }
    );

  };
}
