{ denTest, ... }:
let
  # D1 F1: mkDrained's walk (resolve.nix) never runs policy dispatch, so a
  # pipe-arg-deferred child that registers a policy effect (here, a
  # `resolve.to`) alongside direct class content used to deliver the direct
  # half and drop the policy half with no diagnostic. Each arm gets its own
  # fixture: the residue guard throws for the WHOLE scope's drain fold, so a
  # shared multi-arm `includes` list (fine for D1's other suites) would make
  # every cell in the same host config throw together here.

  # ARM A — pipe-arg deferred, carrying BOTH direct class content (10300)
  # AND a scope-pushing policy (would deliver 10310). The policy half is the
  # one that used to vanish silently.
  fixtureDeferred = den: {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.quirks.firewall.description = "Firewall port declarations";

    den.policies.p-def = _: [
      (den.lib.policy.resolve.to "gA" {
        gA = {
          name = "a";
        };
      })
    ];
    den.schema.gA.includes = [ den.aspects.leaf-a ];
    den.aspects.leaf-a.nixos.networking.firewall.allowedTCPPorts = [ 10310 ];

    den.aspects.igloo = {
      firewall.ports = [ 22 ];
      includes = [
        (
          { firewall, ... }:
          {
            name = "gate2-deferred";
            nixos.networking.firewall.allowedTCPPorts = [ 10300 ];
            includes = [ den.policies.p-def ];
          }
        )
      ];
    };
  };

  # ARM B — the plain (non-deferred) twin of A: same body, same halves.
  # Live control proving the guard is gated on the deferred walk, not on
  # `resolve.to` content itself.
  fixturePlain = den: {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.quirks.firewall.description = "Firewall port declarations";

    den.policies.p-plain = _: [
      (den.lib.policy.resolve.to "gB" {
        gB = {
          name = "b";
        };
      })
    ];
    den.schema.gB.includes = [ den.aspects.leaf-b ];
    den.aspects.leaf-b.nixos.networking.firewall.allowedTCPPorts = [ 10320 ];

    den.aspects.igloo = {
      firewall.ports = [ 22 ];
      includes = [
        {
          name = "gate2-plain";
          nixos.networking.firewall.allowedTCPPorts = [ 10305 ];
          includes = [ den.policies.p-plain ];
        }
      ];
    };
  };

  # ARM C — pipe-arg deferred, whose OWN `includes` fans over an entity arg.
  # The drain walk has no entity kind, so `user` is neither in-ctx nor a
  # descendant: bind rules the whole child inert and 10410 vanished with no
  # residue in any effect map (D1 F1 arm C). 10400 kept delivering, so the
  # loss showed up as nothing at all.
  fixtureEntityFan = den: {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.quirks.firewall.description = "Firewall port declarations";

    den.aspects.igloo = {
      firewall.ports = [ 22 ];
      includes = [
        (
          { firewall, ... }:
          {
            name = "gate3-deferred";
            nixos.networking.firewall.allowedTCPPorts = [ 10400 ];
            includes = [
              (
                { user, ... }:
                {
                  name = "fan-over-user";
                  nixos.networking.firewall.allowedTCPPorts = [ 10410 ];
                }
              )
            ];
          }
        )
      ];
    };
  };

  # ARM D — the live control for arm C's ruling. The pipe-arg-deferred child
  # legitimately delivers nothing into the drained class, while the run's
  # other scopes deliver normally. A guard written on the ABSENCE of
  # scopedClassImports cannot tell this from arm C and throws here; a guard
  # written on bind's recorded verdict stays silent. Measured both ways: with
  # the absence guard swapped in, this cell goes red and arm C goes green —
  # the two are not interchangeable, and arm C alone would not have caught it.
  fixtureInertElsewhere = den: {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.quirks.firewall.description = "Firewall port declarations";

    den.aspects.tux.homeManager.programs.direnv.enable = true;

    den.aspects.igloo = {
      firewall.ports = [ 22 ];
      nixos.networking.firewall.allowedTCPPorts = [ 10500 ];
      includes = [
        (
          { firewall, ... }:
          {
            name = "gate4-deferred";
          }
        )
      ];
    };
  };
in
{
  flake.tests.d1residue = {
    # Pins the fix: the policy half no longer vanishes silently. It throws,
    # naming the undeliverable kind, instead of dropping it with no trace.
    test-policy-borne-residue-throws-loud = denTest (
      { den, igloo, ... }:
      (fixtureDeferred den)
      // {
        expr = igloo.networking.firewall.allowedTCPPorts;
        expectedError = {
          type = "ThrownError";
          msg = "left undeliverable content";
        };
      }
    );

    # Same scenario, via tryEval instead of expectedError: proves the
    # residue guard is visible to `just ci` independent of the
    # expectedError branch above (see ci.bash's hasExpectedError handling).
    test-policy-borne-residue-throws-loud-under-just-ci = denTest (
      { den, igloo, ... }:
      (fixtureDeferred den)
      // {
        expr = (builtins.tryEval (builtins.deepSeq igloo.networking.firewall.allowedTCPPorts null)).success;
        expected = false;
      }
    );

    # Same shapes, not deferred: both halves must still deliver, in the same
    # run — proves the guard does not touch the ordinary (non-drain) path.
    test-plain-twin-both-halves-deliver = denTest (
      { den, igloo, ... }:
      (fixturePlain den)
      // {
        expr =
          builtins.elem 10305 igloo.networking.firewall.allowedTCPPorts
          && builtins.elem 10320 igloo.networking.firewall.allowedTCPPorts;
        expected = true;
      }
    );

    # ARM C, the exhibit: the entity-fan half must be loud, not absent.
    test-entity-fan-residue-throws-loud = denTest (
      { den, igloo, ... }:
      (fixtureEntityFan den)
      // {
        expr = igloo.networking.firewall.allowedTCPPorts;
        expectedError = {
          type = "ThrownError";
          msg = "left undeliverable content";
        };
      }
    );

    test-entity-fan-residue-throws-loud-under-just-ci = denTest (
      { den, igloo, ... }:
      (fixtureEntityFan den)
      // {
        expr = (builtins.tryEval (builtins.deepSeq igloo.networking.firewall.allowedTCPPorts null)).success;
        expected = false;
      }
    );

    # ARM D, the control: same drain, an aspect that legitimately delivers
    # nothing HERE and delivers at the user scope. Must stay silent.
    test-inert-elsewhere-drains-silently = denTest (
      {
        den,
        igloo,
        tuxHm,
        ...
      }:
      (fixtureInertElsewhere den)
      // {
        expr = [
          (builtins.elem 10500 igloo.networking.firewall.allowedTCPPorts)
          tuxHm.programs.direnv.enable
        ];
        expected = [
          true
          true
        ];
      }
    );
  };
}
