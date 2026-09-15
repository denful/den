# Issue #663: `includes` written on an entity INSTANCE
# (`den.hosts.<system>.<name>.includes`) is accepted and silently dropped.
#
# `resolveEntity` built the entity root aspect's collections from exactly two
# sources — the entity's self-provide (`den.aspects.<name>`) and the
# schema-level collection (`den.schema.<kind>.includes`) — and nothing read
# them off the instance. The instance type is constructed with
# `strict = false`, so its freeform type absorbed the key instead of raising
# "option does not exist": the two behaviours are individually reasonable and
# jointly silent, and the host built with an empty aspect tree.
#
# `includes` is the activation key at every other tier, so the instance
# spelling is the natural guess. Read there too, rather than rejected, and
# read in `resolveEntity` rather than per entity kind, so every kind that
# declares `isEntity` gains it at once.
{ denTest, ... }:
{
  flake.tests.deadbugs.issue-663-instance-includes = {

    test-host-instance-includes-honoured = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.includes = [ den.aspects.base ];
        den.aspects.base.nixos.environment.etc."from-base".text = "yes";

        expr = igloo.environment.etc ? "from-base";
        expected = true;
      }
    );

    # CONTROL: the same aspect through the aspect-level spelling, guarding
    # against a false green from `den.aspects.base` never having delivered at
    # all. The failure mode here is "produces a plausible value", so the pair
    # is what discriminates it.
    test-control-aspect-includes-honoured = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.aspects.igloo.includes = [ den.aspects.base ];
        den.aspects.base.nixos.environment.etc."from-base".text = "yes";

        expr = igloo.environment.etc ? "from-base";
        expected = true;
      }
    );

    # `excludes` shares the instance position and was dropped by the same
    # omission, so it is pinned in the same place: the schema tier includes a
    # policy for every host, the instance excludes it.
    test-host-instance-excludes-honoured = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.excludes = [ den.policies.marker ];

        den.policies.marker =
          { host, ... }: [ (den.lib.policy.include { nixos.environment.etc."marker".text = host.name; }) ];
        den.schema.host.includes = [ den.policies.marker ];

        expr = igloo.environment.etc ? "marker";
        expected = false;
      }
    );

    # CONTROL for the excludes cell: without the instance exclude the schema
    # policy does fire, so the assertion above reads a suppression rather
    # than a policy that never delivered.
    test-control-schema-policy-fires = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };

        den.policies.marker =
          { host, ... }: [ (den.lib.policy.include { nixos.environment.etc."marker".text = host.name; }) ];
        den.schema.host.includes = [ den.policies.marker ];

        expr = igloo.environment.etc.marker.text or "<missing>";
        expected = "igloo";
      }
    );

  };
}
