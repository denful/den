# isWalkStampedName tested a name's SHAPE (".*:[0-9]+(/.*)?") to decide
# whether the walk had stamped it, rather than testing whether the walk
# actually had. An author-written name in that shape — "gcc:14", the
# ordinary package-name:version convention — was mistaken for a walk stamp,
# excluded from the inline-chain fill, and read as root: two owners' "gcc:14"
# collide onto one identity and gate dedup drops one, the exact defect this
# task exists to close. "gcc14" (no colon) is the control and must keep
# working the whole time.
{ denTest, ... }:
{
  flake.tests.deadbugs.colon-digit-named-inline-include = {

    test-inline-includes-named-with-colon-digit-both-deliver = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.alpha
          den.aspects.beta
        ];

        den.aspects.alpha.includes = [
          {
            name = "gcc:14";
            nixos.environment.etc."alpha".text = "yes";
          }
        ];

        den.aspects.beta.includes = [
          {
            name = "gcc:14";
            nixos.environment.etc."beta".text = "yes";
          }
        ];

        expr = {
          alpha = igloo.environment.etc ? "alpha";
          beta = igloo.environment.etc ? "beta";
        };
        expected = {
          alpha = true;
          beta = true;
        };
      }
    );

    test-inline-includes-named-with-colon-digit-have-distinct-identities = denTest (
      { den, ... }:
      let
        nodes = builtins.filter (n: n.name == "gcc:14") den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.alpha
          den.aspects.beta
        ];

        den.aspects.alpha.includes = [
          {
            name = "gcc:14";
            nixos.environment.etc."alpha".text = "yes";
          }
        ];

        den.aspects.beta.includes = [
          {
            name = "gcc:14";
            nixos.environment.etc."beta".text = "yes";
          }
        ];

        expr = {
          count = builtins.length nodes;
          identities = builtins.sort builtins.lessThan (map (n: n.identity) nodes);
        };
        expected = {
          count = 2;
          identities = [
            "alpha/gcc:14"
            "beta/gcc:14"
          ];
        };
      }
    );

    # CONTROL: same shape of test, no colon in the name. Must stay green
    # throughout — falsifies a fix that accidentally widens exclusion rather
    # than narrowing it to an actual walk stamp.
    test-control-colonless-name-stays-distinct = denTest (
      { den, ... }:
      let
        nodes = builtins.filter (n: n.name == "gcc14") den.hosts.x86_64-linux.igloo.aspects;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.alpha
          den.aspects.beta
        ];

        den.aspects.alpha.includes = [
          {
            name = "gcc14";
            nixos.environment.etc."alpha".text = "yes";
          }
        ];

        den.aspects.beta.includes = [
          {
            name = "gcc14";
            nixos.environment.etc."beta".text = "yes";
          }
        ];

        expr = {
          count = builtins.length nodes;
          identities = builtins.sort builtins.lessThan (map (n: n.identity) nodes);
        };
        expected = {
          count = 2;
          identities = [
            "alpha/gcc14"
            "beta/gcc14"
          ];
        };
      }
    );

  };
}
