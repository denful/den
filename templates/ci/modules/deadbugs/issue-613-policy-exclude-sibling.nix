# #613 analog for POLICY-NAME exclusion (dispatch-policies / policy-schema late
# filter). Sibling parity: one host excluding a POLICY must not suppress a sibling
# host that includes+fires it. Companion to issue-613-exclude-sibling-isolation
# (aspect-content excludes). Both flavors now route through scopedConstraintsFor
# (entity-scoped + schema-broadcast), so the fleet-wide leak is gone while
# schema-tier (den.schema.KIND.excludes) excludes still broadcast.
{ denTest, ... }:
{
  flake.tests.deadbugs.issue-613-policy-exclude-sibling = {

    # iceberg excludes the policy, igloo includes it → igloo must still fire it.
    test-sibling-policy-exclude-does-not-suppress-includer = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.add-marker = _: [
          (den.lib.policy.include { nixos.environment.variables.MARKER = "yes"; })
        ];
        den.aspects.iceberg.excludes = [ den.policies.add-marker ];
        den.aspects.igloo.includes = [ den.policies.add-marker ];

        expr = igloo.environment.variables.MARKER or "absent";
        expected = "yes";
      }
    );

    # swapped: igloo excludes, iceberg includes → iceberg must still fire it.
    test-sibling-policy-exclude-does-not-suppress-includer-swapped = denTest (
      { den, iceberg, ... }:
      {
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.add-marker = _: [
          (den.lib.policy.include { nixos.environment.variables.MARKER = "yes"; })
        ];
        den.aspects.iceberg.includes = [ den.policies.add-marker ];
        den.aspects.igloo.excludes = [ den.policies.add-marker ];

        expr = iceberg.environment.variables.MARKER or "absent";
        expected = "yes";
      }
    );
  };
}
