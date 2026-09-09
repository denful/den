# N real hosts, built and forced individually. Companion to entity-scale.nix
# (see its header for what the rest of the performance suite does NOT cover).
#
# Every host carries its own copy of a SAME-NAMED policy (`tools`), included
# via den.schema.host.includes so it registers once per host scope — this is
# the shape D4 (nix/lib/aspects/fx/handlers/constraint.nix `isPolicyExcluded`)
# needs to be visible at all: policyClaimsByName."name:tools" accumulates one
# claim per host regardless of scope, while each host's own scoped registry
# keeps exactly one. One host excludes the policy by rawRef (R > 0) so the
# cell also proves exclude resolution still names the right claimant once N
# grows past 1. This cell asserts correctness only — it is not a timing
# instrument; use `just bench` for that, with N raised well past this file's
# default.
#
# Sizing: bump `n` below to scale. Do NOT raise the COMMITTED default: N=1000
# alone, on unmodified den, hits rc=1 at roughly 43GB — a harness memory
# ceiling, not a mechanism cost. n=5 here costs a few seconds under
# `nix-unit --flake ./templates/ci#.tests.performance`.
{ denTest, lib, ... }:
let
  n = 5;
  fleetNames = lib.genList (i: "fleet${toString i}") n;
  excludedHost = builtins.head fleetNames;
in
{
  flake.tests.performance.fleet = {

    test-fleet-scale = denTest (
      {
        den,
        config,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux = lib.genAttrs fleetNames (_: {
          users.tux = { };
        });

        den.policies.tools =
          { host, ... }: [ (den.lib.policy.include { nixos.environment.variables.TOOLS = host.name; }) ];
        den.schema.host.includes = [ den.policies.tools ];

        den.aspects.${excludedHost}.excludes = [ den.policies.tools ];

        expr = {
          # length ∘ filter forces EVERY non-excluded host's built config.
          # builtins.all short-circuits on the first false and would silently
          # time N=1 while claiming to have checked all of them.
          built = builtins.length (
            lib.filter (
              name: (config.flake.nixosConfigurations.${name}.config.environment.variables.TOOLS or null) == name
            ) (lib.filter (name: name != excludedHost) fleetNames)
          );
          excluded =
            config.flake.nixosConfigurations.${excludedHost}.config.environment.variables.TOOLS or "absent";
          # control, independent of `built`: every host actually registered
          # a nixosConfiguration, regardless of whether its content landed
          # correctly. If `built` fell short of `singles - 1` while `singles`
          # still read `n`, that would mean hosts built but with wrong
          # content — a different failure than hosts never building at all.
          singles = builtins.length (
            lib.filter (name: config.flake.nixosConfigurations ? ${name}) fleetNames
          );
        };
        expected = {
          built = n - 1;
          excluded = "absent";
          singles = n;
        };
      }
    );

  };
}
