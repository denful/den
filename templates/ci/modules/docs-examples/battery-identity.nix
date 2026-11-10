# The examples in docs/src/content/docs/reference/batteries.mdx ("Battery
# identity and excludes") that no other cell evaluates exactly.
{ denTest, lib, ... }:
let
  twoSets = den: {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.aspects.igloo.includes = [
      (den.batteries.unfree [ "z1" ])
      (den.batteries.unfree [ "z2" ])
    ];
  };
in
{
  flake.tests.docs-battery-identity = {
    test-exclude-battery-removes-both = denTest (
      { den, igloo, ... }:
      {
        imports = [ (twoSets den) ];
        den.aspects.igloo.excludes = [ den.batteries.unfree ];
        expr = igloo.unfree.packages;
        expected = [ ];
      }
    );
    test-exclude-one-use = denTest (
      { den, igloo, ... }:
      {
        imports = [ (twoSets den) ];
        den.aspects.igloo.excludes = [ (den.batteries.unfree [ "z1" ]) ];
        expr = igloo.unfree.packages;
        expected = [ "z2" ];
      }
    );
  };
}
