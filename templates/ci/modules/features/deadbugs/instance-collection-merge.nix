# Reported on #678 by theutz: two files each writing
# `den.hosts.<system>.<name>.includes` kept one list and dropped the other,
# with no conflict warning.
#
# `den.hosts`' freeform type merged with `lib.recursiveUpdate`, which treats a
# list as an opaque leaf, so one definition overwrote the other. An attrset key
# under the same two definitions merged normally, which is what made it look
# like the collection simply had no effect.
#
# Latent until #663 made instance-level collections mean something. Before
# that they were read by nothing, so there was no way to notice which list
# survived.
{ denTest, ... }:
{
  flake.tests.deadbugs.instance-collection-merge = {

    test-includes-merge-across-definitions = denTest (
      { den, igloo, ... }:
      {
        imports = [
          { den.hosts.x86_64-linux.igloo.includes = [ den.aspects.one ]; }
          { den.hosts.x86_64-linux.igloo.includes = [ den.aspects.two ]; }
        ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.one.nixos.environment.etc."one".text = "y";
        den.aspects.two.nixos.environment.etc."two".text = "y";

        expr = {
          one = igloo.environment.etc ? "one";
          two = igloo.environment.etc ? "two";
        };
        expected = {
          one = true;
          two = true;
        };
      }
    );

    # `excludes` shares the freeform type, so it shared the defect. Two files
    # each excluding one policy must suppress both, not whichever list won.
    test-excludes-merge-across-definitions = denTest (
      { den, igloo, ... }:
      {
        imports = [
          { den.hosts.x86_64-linux.igloo.excludes = [ den.policies.alpha ]; }
          { den.hosts.x86_64-linux.igloo.excludes = [ den.policies.beta ]; }
        ];
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.alpha = _: [
          (den.lib.policy.include { nixos.environment.etc."alpha".text = "y"; })
        ];
        den.policies.beta = _: [
          (den.lib.policy.include { nixos.environment.etc."beta".text = "y"; })
        ];
        den.schema.host.includes = [
          den.policies.alpha
          den.policies.beta
        ];

        expr = {
          alpha = igloo.environment.etc ? "alpha";
          beta = igloo.environment.etc ? "beta";
        };
        expected = {
          alpha = false;
          beta = false;
        };
      }
    );

    # CONTROL for the excludes cell: the two policies do fire when nothing
    # excludes them, so the absences above read as suppression rather than as
    # policies that never delivered.
    test-control-both-policies-fire = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.alpha = _: [
          (den.lib.policy.include { nixos.environment.etc."alpha".text = "y"; })
        ];
        den.policies.beta = _: [
          (den.lib.policy.include { nixos.environment.etc."beta".text = "y"; })
        ];
        den.schema.host.includes = [
          den.policies.alpha
          den.policies.beta
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

    # Declaration order is preserved. Concatenating in either order makes both
    # entries present, so the cells above pass under a reversed merge too;
    # this is what pins the direction, since include order decides which
    # aspect's content wins a conflict.
    test-collection-merge-keeps-declaration-order = denTest (
      { den, config, ... }:
      {
        imports = [
          { den.hosts.x86_64-linux.igloo.includes = [ "A" ]; }
          { den.hosts.x86_64-linux.igloo.includes = [ "B" ]; }
        ];

        expr = config.den.hosts.x86_64-linux.igloo.includes;
        expected = [
          "A"
          "B"
        ];
      }
    );

    # An attrset key merged correctly throughout, and still must. This is the
    # arm that localised the defect to list leaves rather than to the
    # collection keys or to the registry's recursion.
    test-attrset-keys-still-merge = denTest (
      { den, config, ... }:
      {
        imports = [
          { den.hosts.x86_64-linux.igloo.users.alice = { }; }
          { den.hosts.x86_64-linux.igloo.users.bob = { }; }
        ];

        expr = builtins.attrNames config.den.hosts.x86_64-linux.igloo.users;
        expected = [
          "alice"
          "bob"
        ];
      }
    );

  };
}
