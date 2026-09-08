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

    # PE / PE3: excludeIdentity resolves a policy exclude to its bare name,
    # but post-Task-5 same-named claimants are no longer all addressable by
    # that name — only whichever one registered FIRST keeps it; later
    # claimants get a chain-qualified identity (children.nix registerPolicy).
    # `excludes = [ betaTools ]` names a SPECIFIC record, but the bare-name
    # identity it resolves to belongs to whichever claimant registered
    # first — alpha here, since it's first in `includes`. PE3 is
    # byte-identical with `includes` reversed: same `excludes`, but now beta
    # registers first and the bare name happens to land on the right
    # claimant. The pair together is the order-dependence proof: an authored
    # exclude must mean the same thing regardless of its target's position.
    test-pe-exclude-targets-wrong-same-named-claimant = denTest (
      { den, igloo, ... }:
      let
        alphaTools = den.lib.policy.mkPolicy "tools" (_: [
          (den.lib.policy.include { nixos.environment.variables.ALPHA_MARKER = "yes"; })
        ]);
        betaTools = den.lib.policy.mkPolicy "tools" (_: [
          (den.lib.policy.include { nixos.environment.variables.BETA_MARKER = "yes"; })
        ]);
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo = {
          includes = [
            alphaTools
            betaTools
          ];
          excludes = [ betaTools ];
        };

        expr = {
          alpha-fires = igloo.environment.variables ? ALPHA_MARKER;
          beta-excluded = !(igloo.environment.variables ? BETA_MARKER);
        };
        expected = {
          alpha-fires = true;
          beta-excluded = true;
        };
      }
    );

    test-pe3-same-scenario-includes-order-reversed = denTest (
      { den, igloo, ... }:
      let
        alphaTools = den.lib.policy.mkPolicy "tools" (_: [
          (den.lib.policy.include { nixos.environment.variables.ALPHA_MARKER = "yes"; })
        ]);
        betaTools = den.lib.policy.mkPolicy "tools" (_: [
          (den.lib.policy.include { nixos.environment.variables.BETA_MARKER = "yes"; })
        ]);
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo = {
          includes = [
            betaTools
            alphaTools
          ];
          excludes = [ betaTools ];
        };

        expr = {
          alpha-fires = igloo.environment.variables ? ALPHA_MARKER;
          beta-excluded = !(igloo.environment.variables ? BETA_MARKER);
        };
        expected = {
          alpha-fires = true;
          beta-excluded = true;
        };
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
