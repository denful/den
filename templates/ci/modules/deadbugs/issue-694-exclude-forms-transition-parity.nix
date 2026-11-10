# Every exclude form stops a battery's transition default, as the excludes list
# does: a policy.exclude effect, early (an included policy) or at dispatch
# (a schema policy), pairs the battery with its default too. Reported in an
# external review.
{ denTest, lib, ... }:
let
  base = {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.aspects.tux.nixos.environment.etc.own.text = "x";
    den.aspects.tux.provides.to-hosts.nixos.environment.etc.prov.text = "x";
  };
  tr = {
    den.internal.transitionDefaults = lib.mkForce true;
  };
  ack = {
    den.migrations.user-host-content.acknowledged = true;
  };
  out = igloo: {
    own = igloo.environment.etc ? own;
    prov = igloo.environment.etc ? prov;
  };
  # forms: L = aspect excludes list; E = policy.exclude from igloo's includes
  # (early path); S = the same policy on den.schema.host.includes.
  form =
    den: f: x:
    if f == "L" then
      { den.aspects.igloo.excludes = [ x ]; }
    else if f == "E" then
      {
        den.aspects.igloo.includes = [
          (den.lib.policy.mkPolicy "ex" ({ host, ... }: [ (den.lib.policy.exclude x) ]))
        ];
      }
    else
      {
        den.schema.host.includes = [
          (den.lib.policy.mkPolicy "ex" ({ host, ... }: [ (den.lib.policy.exclude x) ]))
        ];
      };
  cells =
    mode: battery: expected:
    lib.listToAttrs (
      map
        (f: {
          name = "test-${mode}-${battery}-${f}";
          value = denTest (
            { den, igloo, ... }:
            {
              imports = [
                base
                (
                  if mode == "tr" then
                    tr
                  else if mode == "ack" then
                    ack
                  else
                    { }
                )
                (form den f den.batteries.${battery})
              ]
              ++ lib.optional (mode == "explicit") { den.aspects.igloo.includes = [ den.batteries.${battery} ]; };
              expr = out igloo;
              inherit expected;
            }
          );
        })
        [
          "L"
          "E"
          "S"
        ]
    );
in
{
  flake.tests.exclude-forms-transition-parity =
    # Controls (no exclude).
    {
      test-ctl-tr = denTest (
        { den, igloo, ... }:
        {
          imports = [
            base
            tr
          ];
          expr = out igloo;
          expected = {
            own = true;
            prov = true;
          };
        }
      );
      test-ctl-explicit = denTest (
        { den, igloo, ... }:
        {
          imports = [ base ];
          den.aspects.igloo.includes = [
            den.batteries.user-aspects
            den.batteries.mutual-provider
          ];
          expr = out igloo;
          expected = {
            own = true;
            prov = true;
          };
        }
      );
    }
    # Transition on: excluding a battery stops its default.
    // cells "tr" "user-aspects" {
      own = false;
      prov = true;
    }
    # mutual-provider alone: user-aspects' default lift still carries the
    # provided content, so every form leaves it, as the list does.
    # exclude-forms-mp-parity excludes user-aspects too and varies this form.
    // cells "tr" "mutual-provider" {
      own = true;
      prov = true;
    }
    # Explicit battery (end state): excluding it stops it.
    // cells "explicit" "user-aspects" {
      own = false;
      prov = false;
    }
    // cells "explicit" "mutual-provider" {
      own = false;
      prov = false;
    };
}
