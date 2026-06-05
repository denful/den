{ denTest, ... }:
{
  flake.tests.issue-525-hasaspect-in-policy-when = {
    # policy.when with host.hasAspect — the original bug report.
    # Was infinite recursion because hasAspect read config.resolved.
    # Fix: policy.when emits conditional aspect; compile-conditional provides
    # entity-shaped stubs with pathSet-based hasAspect, defers on failure.
    test-hasaspect-guard-fires = denTest (
      { den, igloo, ... }:
      let
        inherit (den) aspects;
        inherit (den.lib) policy;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.my-aspect.nixos.programs.git.enable = true;

        den.aspects.igloo.includes = [ aspects.my-aspect ];

        den.schema.host.includes = [
          (policy.when ({ host, ... }: host.hasAspect aspects.my-aspect) {
            nixos.networking.hostName = "guarded";
          })
        ];

        expr = igloo.networking.hostName;
        expected = "guarded";
      }
    );

    # Negative case: guard should suppress when aspect is not present.
    test-hasaspect-guard-suppresses = denTest (
      { den, igloo, ... }:
      let
        inherit (den) aspects;
        inherit (den.lib) policy;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.my-aspect.nixos.programs.git.enable = true;

        # my-aspect is NOT included for igloo
        den.schema.host.includes = [
          (policy.when ({ host, ... }: host.hasAspect aspects.my-aspect) {
            nixos.networking.hostName = "guarded";
          })
        ];

        expr = igloo.networking.hostName;
        expected = "nixos";
      }
    );

    # Works from user aspect includes too.
    test-hasaspect-from-user-scope = denTest (
      { den, igloo, ... }:
      let
        inherit (den) aspects;
        inherit (den.lib) policy;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.my-aspect.nixos.programs.git.enable = true;

        den.aspects.igloo.includes = [ aspects.my-aspect ];

        den.aspects.tux.includes = [
          (policy.when ({ host, ... }: host.hasAspect aspects.my-aspect) {
            nixos.networking.hostName = "from-user-guard";
          })
        ];

        expr = igloo.networking.hostName;
        expected = "from-user-guard";
      }
    );

    # Walk-order independence: guard references an aspect included AFTER the
    # conditional. On first pass the guard fails (my-aspect not yet in pathSet),
    # but drain-conditionals re-evaluates with the final pathSet.
    test-deferred-guard-fires-after-walk = denTest (
      { den, igloo, ... }:
      let
        inherit (den) aspects;
        inherit (den.lib) policy;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.my-aspect.nixos.programs.git.enable = true;

        # Guard comes BEFORE the aspect it checks — tests deferral.
        den.schema.host.includes = [
          (policy.when ({ host, ... }: host.hasAspect aspects.my-aspect) {
            nixos.networking.hostName = "deferred-guard";
          })
        ];

        den.aspects.igloo.includes = [ aspects.my-aspect ];

        expr = igloo.networking.hostName;
        expected = "deferred-guard";
      }
    );

    # forAnyClass variant works.
    test-hasaspect-foranyclass = denTest (
      { den, igloo, ... }:
      let
        inherit (den) aspects;
        inherit (den.lib) policy;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.my-aspect.nixos.programs.git.enable = true;

        den.aspects.igloo.includes = [ aspects.my-aspect ];

        den.schema.host.includes = [
          (policy.when ({ host, ... }: host.hasAspect.forAnyClass aspects.my-aspect) {
            nixos.networking.hostName = "any-class-guard";
          })
        ];

        expr = igloo.networking.hostName;
        expected = "any-class-guard";
      }
    );
  };
}
