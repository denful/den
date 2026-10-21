# insecure-predicate-builder.nix and unfree-predicate-builder.nix ship their
# parent aspect as a raw attrset (no meta) under den.default.includes, and
# their children carry author-written names that already encode the parent's
# path ("insecure-predicate/os", ...). Filling the parent's chain from
# den.default's walk position moved it to "default/insecure-predicate"; the
# same fill on a child then prepended that same "insecure-predicate" a second
# time, on top of the copy already embedded in the child's own name — every
# den configuration includes den.default, so every one was affected.
{ denTest, ... }:
{
  flake.tests.deadbugs.shipped-battery-chain = {

    test-insecure-and-unfree-batteries-keep-shipped-identities = denTest (
      { den, ... }:
      let
        wanted = [
          "insecure-predicate"
          "insecure-predicate/os"
          "insecure-predicate/user"
          "unfree-predicate"
          "unfree-predicate/os"
          "unfree-predicate/user"
        ];
        identities = map (n: n.identity) den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = builtins.sort builtins.lessThan (builtins.filter (i: builtins.elem i wanted) identities);
        expected = builtins.sort builtins.lessThan wanted;
      }
    );

  };
}
