# Reported in GitHub #754, owner ruling 2026-11-08: host-class content from a
# policy nested inside `provides.to-hosts` (or `provides.<host>`) is part of
# what mutual-provider delivers, as that provide's static content is. Den
# records the provider's token on the policy's registry entry where it
# registers, and its includes are emitted under it wherever it fires.
{ denTest, lib, ... }:
let
  shapes = den: {
    host = den.lib.policy.mkPolicy "g" (
      { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
    );
    host-user = den.lib.policy.mkPolicy "g" (
      { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
    );
  };
  nests = {
    n0 = p: { includes = [ p ]; };
    n1 = p: {
      includes = [
        {
          name = "inner";
          includes = [ p ];
        }
      ];
    };
    n2 = p: {
      includes = [
        (
          { host, ... }:
          {
            includes = [ p ];
          }
        )
      ];
    };
  };
  # One cell per shape and nesting, with `extra` and its expected value.
  grid =
    prefix: extra: expect:
    lib.listToAttrs (
      lib.concatMap
        (
          s:
          map (n: {
            name = "test-${prefix}-${s}-${n}";
            value = denTest (
              {
                den,
                igloo,
                config,
                ...
              }:
              {
                imports = [ (extra den) ];
                den.hosts.x86_64-linux.igloo.users.tux = { };
                den.aspects.tux.provides.to-hosts.includes = [ (nests.${n} (shapes den).${s}) ];
                expr = expect.expr { inherit igloo config; };
                expected = expect.value;
              }
            );
          }) (builtins.attrNames nests)
        )
        (
          builtins.attrNames (shapes {
            lib.policy.mkPolicy = _: _: null;
          })
        )
    );
  delivered = {
    expr = { igloo, ... }: igloo.environment.etc ? g;
    value = true;
  };
  explicit = den: { den.schema.host.includes = [ den.batteries.mutual-provider ]; };
  # Both, merged as modules: `//` would drop one's `den`.
  both = den: {
    imports = [
      (explicit den)
      { den.internal.transitionDefaults = lib.mkForce true; }
    ];
  };
  excludedBattery = den: {
    imports = [ (explicit den) ];
    den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
  };
in
{
  flake.tests.deadbugs.issue-754-to-hosts-nested-policy-provenance =
    # The end state, mutual-provider explicit: delivered.
    grid "end-state-delivers" explicit delivered
    # The transition, mutual-provider explicit: delivered, and nothing is
    # listed, since the content arrives through the explicit battery.
    // grid "transition-delivers" both delivered
    // grid "transition-lists-nothing" both {
      expr =
        { config, ... }:
        config.flake.nixosConfigurations.igloo._module.args.denTransitionDefaultLost or [ ];
      value = [ ];
    }
    # Excluding the battery stops it, as it stops the provide's static content.
    // grid "excluded-battery-stops" excludedBattery {
      inherit (delivered) expr;
      value = false;
    }
    // {
      # A policy carrying a provenance-looking field of its own, outside any
      # cross-provider include, is the user's: its host-class include stays
      # with the user in the end state.
      test-own-field-inherits-nothing = denTest (
        { den, igloo, ... }:
        {
          imports = [ (explicit den) ];
          den.hosts.x86_64-linux.igloo.users.tux = { };
          den.aspects.tux.includes = [
            (
              (den.lib.policy.mkPolicy "g" (
                { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
              ))
              // {
                provenance = "tux/to-hosts";
                __fromProvenance = "tux/to-hosts";
              }
            )
          ];
          den.aspects.tux.provides.to-hosts.nixos.environment.etc.real.text = "x";
          expr = {
            g = igloo.environment.etc ? g;
            real = igloo.environment.etc ? real;
          };
          expected = {
            g = false;
            real = true;
          };
        }
      );
    };
}
