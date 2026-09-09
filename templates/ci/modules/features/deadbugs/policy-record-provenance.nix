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
    # bodies) at genuinely DIFFERENT module `loc`s — each aspect's own
    # submodule eval bakes its own name into `loc`, so a fix bucketing by
    # def-position/loc would put them in separate buckets and MISS this
    # collision entirely. They still collide because both land in the same
    # scope's scopedAspectPolicies keyed by the bare name "tools".
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

    # O4 at N=3: the same collision as above, with three sibling same-named
    # claimants instead of two — the exact factory shape
    # `map (t: mkPolicy "tools" (bodyFor t)) [ ... ]`. A qualified identity
    # built only from the parent chain is constant across every claimant
    # sharing that chain, so it distinguishes claimant #1 from the rest but
    # not #2 from #3 — safe at N=2, silent drop at N>=3.
    test-o4-three-same-named-claimants-all-fire = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes =
          map
            (
              t:
              den.lib.policy.mkPolicy "tools" (
                { host, ... }:
                [
                  (den.lib.policy.provide {
                    class = host.class;
                    module.environment.etc."${t}-tools".text = "yes";
                  })
                ]
              )
            )
            [
              "a"
              "b"
              "c"
            ];

        expr = {
          a = igloo.environment.etc ? "a-tools";
          b = igloo.environment.etc ? "b-tools";
          c = igloo.environment.etc ? "c-tools";
        };
        expected = {
          a = true;
          b = true;
          c = true;
        };
      }
    );

    # O4 across an ancestor/descendant scope pair: a host-scope "tools" policy
    # requiring `{ user, ... }` — unbound at the host's own dispatch, so it
    # only fires via policy/schema.nix's late-dispatch pass — and a DIFFERENT
    # user-scope "tools" owned by tux directly must both deliver. Late-dispatch
    # merges the host scope's registrations with a sibling user's BY
    # ownerIdentity (`scopedAspectPolicies.${parentScope} //
    # scopedAspectPolicies.${sib.scopeId}` in emitLateForSibling) — a
    # same-scope-only identity comparison let both keep the bare name "tools",
    # so the merge picked tux's own (already-fired) claim and the host's late
    # policy was filtered out as "already fired" under that name, never
    # reaching tux. Two users are required: the late-dispatch pass only runs
    # when there's more than one sibling (isFanOut); pingu (with no own
    # "tools") is the control showing the host's policy is undisturbed where
    # there's nothing to collide with.
    test-o4-ancestor-descendant-scopes-same-name-both-fire = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.includes = [
          (den.lib.policy.mkPolicy "tools" (
            { user, ... }:
            [
              (den.lib.policy.include {
                homeManager.home.sessionVariables.HOST_TOOLS = user.name;
              })
            ]
          ))
        ];

        den.aspects.tux.includes = [
          (den.lib.policy.mkPolicy "tools" (
            { ... }:
            [
              (den.lib.policy.include {
                homeManager.home.sessionVariables.TUX_OWN_TOOLS = "yes";
              })
            ]
          ))
        ];

        expr = {
          tuxHost = tuxHm.home.sessionVariables.HOST_TOOLS or "absent";
          tuxOwn = tuxHm.home.sessionVariables.TUX_OWN_TOOLS or "absent";
          pinguHost = pinguHm.home.sessionVariables.HOST_TOOLS or "absent";
        };
        expected = {
          tuxHost = "tux";
          tuxOwn = "yes";
          pinguHost = "pingu";
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
