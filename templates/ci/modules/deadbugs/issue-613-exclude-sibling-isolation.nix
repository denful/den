# #613 analog for EXCLUDES — sibling-scope isolation of the constraint registry.
#
# #613 fixed sibling leakage in the conditional-guard hasAspect (the pathSet was
# fleet-wide). This verifies the EXCLUDE path (the constraint registry, applied at
# check-constraint during the tree walk) has the SAME per-entity isolation: one
# host excluding an aspect must NOT suppress a SIBLING host that includes it, and
# vice-versa — regardless of host eval order (iceberg vs igloo).
#
# Mirrors github.com/tschan/den-hasaspect-bug modules/bug.nix (the `bogus` +
# `working` pair). Both must pass: an include on host X delivers the aspect to X
# even when a sibling Y excludes it.
{ denTest, ... }:
{
  flake.tests.deadbugs.issue-613-exclude-sibling-isolation = {

    # iceberg excludes, igloo includes → igloo (the includer) must get the aspect.
    # (the tschan `bogus` case — the sibling exclude must not leak into igloo.)
    test-sibling-exclude-does-not-suppress-includer = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.test.nixos.networking.hostName = "right";
        den.aspects.iceberg.excludes = [ den.aspects.test ];
        den.aspects.igloo.includes = [ den.aspects.test ];

        expr = igloo.networking.hostName;
        expected = "right";
      }
    );

    # symmetric: iceberg includes, igloo excludes → iceberg (the includer) gets it.
    # (the tschan `working` case.)
    test-sibling-exclude-does-not-suppress-includer-swapped = denTest (
      { den, iceberg, ... }:
      {
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.test.nixos.networking.hostName = "right";
        den.aspects.iceberg.includes = [ den.aspects.test ];
        den.aspects.igloo.excludes = [ den.aspects.test ];

        expr = iceberg.networking.hostName;
        expected = "right";
      }
    );
  };
}
