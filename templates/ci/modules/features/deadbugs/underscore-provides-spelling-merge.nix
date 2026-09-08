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
# test-q4-nested-conflict-is-error is a guard, not a regression check: it
# asserts nested's genuine scalar conflict IS an error, which is false under
# the intended fix (unifying spelling only, not root's and nested's separate
# merge semantics) and must stay red. A green there means nested started
# erroring like root — a larger change than this file's own scope.
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

    # Guard — see file header. Must stay red.
    test-q4-nested-conflict-is-error = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          { den.aspects.conflictNested.sub.provides.hn.nixos.networking.hostName = "hA"; }
          { den.aspects.conflictNested.sub._.hn.nixos.networking.hostName = "hB"; }
        ];

        den.aspects.igloo.includes = [ den.aspects.conflictNested.sub.hn ];

        expr =
          let
            attempt = builtins.tryEval igloo.networking.hostName;
          in
          if attempt.success then attempt.value else "ERROR";
        expected = "ERROR";
      }
    );
  };
}
