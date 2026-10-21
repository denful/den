# Regression for denful/den#613: `host.hasAspect` inside a `policy.when` guard
# must reflect ONLY the guarded host's own (subtree + inherited) membership —
# NOT aspects another host included earlier in the fleet walk. The bug was that
# guards consulted the flat fleet-wide in-flight pathSet, so membership leaked
# across sibling hosts in an eval-order-dependent way.
{ denTest, ... }:
{
  flake.tests.hasaspect-guard-cross-host = {

    # The reported case: iceberg includes `test`; igloo does NOT, but guards on
    # `host.hasAspect test`. igloo's guard must be FALSE (→ hostName stays the
    # default "nixos"), even though iceberg was walked first and included test.
    test-sibling-include-does-not-leak = denTest (
      {
        den,
        igloo,
        ...
      }:
      let
        inherit (den.lib) policy;
      in
      {
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.test.nixos = { };
        den.aspects.iceberg.includes = [ den.aspects.test ];
        den.aspects.igloo.includes = [
          (policy.when ({ host, ... }: host.hasAspect den.aspects.test) {
            nixos.networking.hostName = "wrong";
          })
        ];

        expr = igloo.networking.hostName;
        expected = "nixos";
      }
    );

    # Order-independence: same topology, but the guarded host is checked while
    # the OTHER host (igloo) includes test. iceberg's guard must still be FALSE.
    test-sibling-include-does-not-leak-reversed = denTest (
      {
        den,
        iceberg,
        ...
      }:
      let
        inherit (den.lib) policy;
      in
      {
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.test.nixos = { };
        den.aspects.igloo.includes = [ den.aspects.test ];
        den.aspects.iceberg.includes = [
          (policy.when ({ host, ... }: host.hasAspect den.aspects.test) {
            nixos.networking.hostName = "wrong";
          })
        ];

        expr = iceberg.networking.hostName;
        expected = "nixos";
      }
    );

    # The host's OWN include must still be seen by its guard (true positive).
    test-own-include-fires = denTest (
      {
        den,
        igloo,
        ...
      }:
      let
        inherit (den.lib) policy;
      in
      {
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.test.nixos = { };
        den.aspects.igloo.includes = [
          den.aspects.test
          (policy.when ({ host, ... }: host.hasAspect den.aspects.test) {
            nixos.networking.hostName = "fired";
          })
        ];

        expr = igloo.networking.hostName;
        expected = "fired";
      }
    );

    # Ancestor inheritance must still be seen: an aspect delivered to ALL hosts
    # via `den.default` is in every host's inherited membership, so the guard
    # fires (the scope walk includes ancestors, not just the host's own scope).
    test-default-include-inherited-fires = denTest (
      {
        den,
        igloo,
        ...
      }:
      let
        inherit (den.lib) policy;
      in
      {
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.test.nixos = { };
        den.default.includes = [ den.aspects.test ];
        den.aspects.igloo.includes = [
          (policy.when ({ host, ... }: host.hasAspect den.aspects.test) {
            nixos.networking.hostName = "fired";
          })
        ];

        expr = igloo.networking.hostName;
        expected = "fired";
      }
    );
  };
}
