# Policy records carry no provenance today: `identity.key` reads a policy's
# bare `name` (it has no `meta.aspect-chain` to build on), so two `mkPolicy
# "tools"` records owned by different aspects both compute the identity
# "tools" and collide in scopedAspectPolicies — one owner's registration
# silently overwrites the other's (O4).
#
# The tempting wrong fix is to key a policy's identity off its inclusion
# site unconditionally. That passes O4 but fails its control: a single
# `den.policies.foo` referenced from two aspects is ONE registration, not
# two, and must still fire once (O5).
{ denTest, ... }:
{
  flake.tests.deadbugs.policy-record-provenance = {

    # O4: two inline mkPolicy records sharing the bare name "tools", each
    # owned by a different aspect, must both deliver. Today only one
    # survives — whichever owner's registration is walked last.
    test-o4-two-inline-mkpolicy-same-name-both-fire = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.alpha
          den.aspects.beta
        ];

        den.aspects.alpha.includes = [
          (den.lib.policy.mkPolicy "tools" (
            { host, ... }:
            [
              (den.lib.policy.provide {
                class = host.class;
                module.environment.etc."alpha-tools".text = "yes";
              })
            ]
          ))
        ];

        den.aspects.beta.includes = [
          (den.lib.policy.mkPolicy "tools" (
            { host, ... }:
            [
              (den.lib.policy.provide {
                class = host.class;
                module.environment.etc."beta-tools".text = "yes";
              })
            ]
          ))
        ];

        expr = {
          alpha = igloo.environment.etc ? "alpha-tools";
          beta = igloo.environment.etc ? "beta-tools";
        };
        expected = {
          alpha = true;
          beta = true;
        };
      }
    );

    # O4 variant: the same collision reached through an aspect's own nested
    # `.policies.<name>` registry instead of an inline mkPolicy literal. Two
    # different aspects each declare their OWN "tools" policy (different
    # bodies) — a registry-key-only fix (bucketing purely by the module
    # system's `loc`, which is submodule-local and identical for both
    # aspects' "policies.tools" option) must still tell them apart by raw
    # value, not by the bucket key alone.
    test-o4-two-aspect-own-policies-same-name-both-fire = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.gamma
          den.aspects.delta
        ];

        den.aspects.gamma.policies.tools =
          { host, ... }:
          [
            (den.lib.policy.provide {
              class = host.class;
              module.environment.etc."gamma-tools".text = "yes";
            })
          ];
        den.aspects.gamma.includes = [ den.aspects.gamma.policies.tools ];

        den.aspects.delta.policies.tools =
          { host, ... }:
          [
            (den.lib.policy.provide {
              class = host.class;
              module.environment.etc."delta-tools".text = "yes";
            })
          ];
        den.aspects.delta.includes = [ den.aspects.delta.policies.tools ];

        expr = {
          gamma = igloo.environment.etc ? "gamma-tools";
          delta = igloo.environment.etc ? "delta-tools";
        };
        expected = {
          gamma = true;
          delta = true;
        };
      }
    );

    # O5 (O4's control): a SHARED `den.policies.foo`, included from two
    # different aspects, is one registration referenced twice — not two
    # authored policies. A fix that splits identity by inclusion site
    # unconditionally makes it fire twice; `environment.etc` is `types.lines`
    # so a double fire is visible as "yes\nyes" rather than "yes".
    test-o5-shared-registry-policy-fires-once = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.shared-tool =
          { host, ... }:
          [
            (den.lib.policy.provide {
              class = host.class;
              module.environment.etc.shared-tool.text = "yes";
            })
          ];

        den.aspects.igloo.includes = [
          den.aspects.epsilon
          den.aspects.zeta
        ];

        den.aspects.epsilon.includes = [ den.policies.shared-tool ];
        den.aspects.zeta.includes = [ den.policies.shared-tool ];

        expr = igloo.environment.etc.shared-tool.text;
        expected = "yes";
      }
    );

  };
}
