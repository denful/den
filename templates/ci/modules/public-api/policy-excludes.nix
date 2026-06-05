{ denTest, lib, ... }:
{
  flake.tests.policy-excludes = {

    # A policy excluded via meta.excludes does not fire.
    test-excluded-policy-does-not-fire = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.add-marker = _: [
          (den.lib.policy.include {
            nixos.environment.variables.EXCLUDED_MARKER = "yes";
          })
        ];
        den.aspects.igloo = {
          includes = [ den.policies.add-marker ];
          excludes = [ den.policies.add-marker ];
        };

        expr = igloo.environment.variables.EXCLUDED_MARKER or "absent";
        expected = "absent";
      }
    );

    # A policy NOT in excludes still fires normally.
    test-non-excluded-policy-fires = denTest (
      {
        den,
        igloo,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.my-enrichment =
          { host, ... }:
          [
            (den.lib.policy.resolve {
              myFlag = true;
            })
          ];
        den.aspects.igloo = {
          policies.to-users =
            {
              host,
              user,
              myFlag ? false,
              ...
            }:
            lib.optional myFlag (
              den.lib.policy.include {
                homeManager.home.sessionVariables.ENRICHED = "yes";
              }
            );
          includes = [
            den.policies.my-enrichment
            den.aspects.igloo.policies.to-users
          ];
        };

        expr = tuxHm.home.sessionVariables.ENRICHED or "no";
        expected = "yes";
      }
    );

    # Parent excludes are authoritative — child includes cannot override.
    test-parent-excludes-authoritative = denTest (
      { den, igloo, ... }:
      let
        childAspect = {
          includes = [ den.policies.blocked-pol ];
        };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.blocked-pol = _: [
          (den.lib.policy.include {
            nixos.environment.variables.BLOCKED_MARKER = "yes";
          })
        ];
        den.aspects.igloo = {
          includes = [ childAspect ];
          excludes = [ den.policies.blocked-pol ];
        };

        expr = igloo.environment.variables.BLOCKED_MARKER or "absent";
        expected = "absent";
      }
    );

  };
}
