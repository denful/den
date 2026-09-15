# mkParametricBase (nix/lib/aspects/fx/aspect.nix) rebuilt a parametric-resolved
# aspect from an explicit carry-forward whitelist (name, meta, into, provides)
# instead of merging onto the original, so a walk-stamped child that also went
# through compile-parametric (e.g. a class-content module naming a descendant
# entity kind, promoted by compile.nix's router) lost its __walkStamped marker
# while its walk-stamped name string survived. compile-static then re-fired the
# chain fill on re-entry, double-encoding the segment already embedded in the
# name. Live on the stock igloo/tux fixture with no user aspects at all.
{ denTest, lib, ... }:
{
  flake.tests.deadbugs.walkstamp-parametric-roundtrip = {

    test-walk-stamped-parametric-child-identity-does-not-double = denTest (
      { den, ... }:
      let
        identities = map (n: n.identity) den.hosts.x86_64-linux.igloo.aspects;
        # A doubled identity repeats one segment back-to-back, e.g.
        # "user/user/<anon>:5" — general shape, not tied to a specific index.
        hasAdjacentDup =
          segs:
          builtins.any (i: i > 0 && builtins.elemAt segs i == builtins.elemAt segs (i - 1)) (
            builtins.genList (i: i) (builtins.length segs)
          );
        doubled = builtins.filter (i: hasAdjacentDup (lib.splitString "/" i)) identities;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = doubled;
        expected = [ ];
      }
    );

  };
}
