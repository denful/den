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
  };
}
