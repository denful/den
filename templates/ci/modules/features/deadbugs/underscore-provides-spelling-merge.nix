# `_` and `provides` are two spellings of one namespace, built at three
# separate sites in types.nix. Root already merges both spellings of one key
# (mkAliasOptionModule folds `_` into `provides` before the freeform type
# ever sees it); nested used to overwrite instead, and spelling-priority at
# that — `_` always won regardless of which file came first, so reordering
# never recovered the dropped definition.
#
# Each mixed-spelling test uses two separate `imports` fragments so the two
# definitions genuinely come from different files, matching how an author
# would actually split `provides.x` and `_.x` across modules — a single
# literal setting both keys never exercised the cross-file path.
#
# test-q4-root-nested-conflict-diverges pins a fact, not a preference: root
# and nested deliberately still disagree on a genuine scalar conflict (root
# errors, nested last-wins) — closing that gap is the strong reading of O8
# and out of scope for this task. It must read green; if it goes red, either
# position's conflict behaviour changed and that's a bigger change than this
# file's own scope.
{ denTest, ... }:
{
  flake.tests.deadbugs.underscore-provides-spelling-merge = {

    test-o8-root-mixed-spellings-merge = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          { den.aspects.mixedRoot.provides.x.nixos.boot.kernelParams = [ "kpA" ]; }
          { den.aspects.mixedRoot._.x.nixos.boot.kernelParams = [ "kpB" ]; }
        ];

        den.aspects.igloo.includes = [ den.aspects.mixedRoot.x ];

        expr = {
          hasA = builtins.elem "kpA" igloo.boot.kernelParams;
          hasB = builtins.elem "kpB" igloo.boot.kernelParams;
        };
        expected = {
          hasA = true;
          hasB = true;
        };
      }
    );

    test-o8-root-mixed-spellings-merge-reversed = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          { den.aspects.mixedRootRev._.x.nixos.boot.kernelParams = [ "kpB" ]; }
          { den.aspects.mixedRootRev.provides.x.nixos.boot.kernelParams = [ "kpA" ]; }
        ];

        den.aspects.igloo.includes = [ den.aspects.mixedRootRev.x ];

        expr = {
          hasA = builtins.elem "kpA" igloo.boot.kernelParams;
          hasB = builtins.elem "kpB" igloo.boot.kernelParams;
        };
        expected = {
          hasA = true;
          hasB = true;
        };
      }
    );

    test-o8-nested-mixed-spellings-merge = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          { den.aspects.mixedNested.sub.provides.x.nixos.boot.kernelParams = [ "kpA" ]; }
          { den.aspects.mixedNested.sub._.x.nixos.boot.kernelParams = [ "kpB" ]; }
        ];

        den.aspects.igloo.includes = [ den.aspects.mixedNested.sub.x ];

        expr = {
          hasA = builtins.elem "kpA" igloo.boot.kernelParams;
          hasB = builtins.elem "kpB" igloo.boot.kernelParams;
        };
        expected = {
          hasA = true;
          hasB = true;
        };
      }
    );

    test-o8-nested-mixed-spellings-merge-reversed = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          { den.aspects.mixedNestedRev.sub._.x.nixos.boot.kernelParams = [ "kpB" ]; }
          { den.aspects.mixedNestedRev.sub.provides.x.nixos.boot.kernelParams = [ "kpA" ]; }
        ];

        den.aspects.igloo.includes = [ den.aspects.mixedNestedRev.sub.x ];

        expr = {
          hasA = builtins.elem "kpA" igloo.boot.kernelParams;
          hasB = builtins.elem "kpB" igloo.boot.kernelParams;
        };
        expected = {
          hasA = true;
          hasB = true;
        };
      }
    );

    # See file header. Root and nested target different options so one
    # side's raw conflicting defs can't also poison the other's already-
    # collapsed value in the same host evaluation.
    test-q4-root-nested-conflict-diverges = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          { den.aspects.conflictRoot.provides.hn.nixos.networking.hostName = "hA"; }
          { den.aspects.conflictRoot._.hn.nixos.networking.hostName = "hB"; }
          { den.aspects.conflictNested.sub.provides.tz.nixos.time.timeZone = "hA"; }
          { den.aspects.conflictNested.sub._.tz.nixos.time.timeZone = "hB"; }
        ];

        den.aspects.igloo.includes = [
          den.aspects.conflictRoot.hn
          den.aspects.conflictNested.sub.tz
        ];

        expr =
          let
            tryOr =
              v:
              let
                a = builtins.tryEval v;
              in
              if a.success then a.value else "ERROR";
          in
          {
            root = tryOr igloo.networking.hostName;
            nested = tryOr igloo.time.timeZone;
          };
        expected = {
          root = "ERROR";
          nested = "hB";
        };
      }
    );

    # mergeFunctions' battery branch (import-tree/forward-style attrsets
    # carrying __functor) used to read only fn.provides and ignore fn._
    # outright — no host eval needed, this calls providerType.merge
    # directly on a battery-shaped def to pin the forwarding itself.
    test-q4-battery-underscore-write-forwards = denTest (
      { den, ... }:
      let
        merge = den.lib.aspects.types.providerType.merge;
        battery = {
          __functor = self: args: { };
          _.child.nixos.environment.etc."x".text = "y";
        };
        merged =
          merge
            [ "probe" ]
            [
              {
                file = "<test>";
                value = battery;
              }
            ];
      in
      {
        expr = {
          direct = merged ? child;
          viaUnderscore = merged ? _ && merged._ ? child;
          viaProvides = merged ? provides && merged.provides ? child;
        };
        expected = {
          direct = true;
          viaUnderscore = true;
          viaProvides = true;
        };
      }
    );

    # Same fields as the cell above, but through a real declaration
    # (den.aspects.battHolder.provides.batt) rather than a hand-minted def
    # handed straight to merge — pins the behaviour a consumer actually sees,
    # not just the internal signature.
    test-rvb-consumer-battery-underscore = denTest (
      { den, ... }:
      {
        den.aspects.battHolder.provides.batt = {
          __functor = self: args: { };
          _.child.nixos.environment.etc."x".text = "y";
        };

        expr = {
          direct = den.aspects.battHolder.batt ? child;
          viaUnderscore = den.aspects.battHolder.batt ? _ && den.aspects.battHolder.batt._ ? child;
          viaProvides =
            den.aspects.battHolder.batt ? provides && den.aspects.battHolder.batt.provides ? child;
        };
        expected = {
          direct = true;
          viaUnderscore = true;
          viaProvides = true;
        };
      }
    );
  };
}
