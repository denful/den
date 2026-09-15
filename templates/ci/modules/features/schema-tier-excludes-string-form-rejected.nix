# `den.schema.<kind>.excludes` used to accept a bare string and silently
# exclude nothing — same defect as `den.aspects.*.excludes` before
# 3c5b5227, one tier up, and reaching every schema kind (gen-schema has no
# per-collection `type` for this untyped collection). See
# `excludes-string-form-rejected.nix` for the aspect-tier counterpart.
{ denTest, ... }:
{
  flake.tests.schema-tier-excludes-string-form-rejected = {

    test-schema-excludes-string-form-errors = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.s2-marker = _: [
          (den.lib.policy.include {
            nixos.environment.variables.S2_MARKER = "yes";
          })
        ];
        den.aspects.igloo.includes = [ den.policies.s2-marker ];
        den.schema.host.excludes = [ "s2-marker" ];

        expr = igloo.networking.hostName;
        expectedError = {
          type = "ThrownError";
          msg = "den: den.schema.<kind>.excludes";
        };
      }
    );

    # Uncontested-policy control: a legitimate record-form exclude must
    # still fire, so the cell above isn't vacuous (everything erroring would
    # look identical to the fix working).
    test-schema-excludes-record-form-still-fires = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.s2-marker-b = _: [
          (den.lib.policy.include {
            nixos.environment.variables.S2_MARKER_B = "yes";
          })
        ];
        den.aspects.igloo.includes = [ den.policies.s2-marker-b ];
        den.schema.host.excludes = [ den.policies.s2-marker-b ];

        expr = igloo.environment.variables.S2_MARKER_B or "absent";
        expected = "absent";
      }
    );

    # Breadth: the defect reached every schema kind, not just `host`.
    test-schema-excludes-string-form-errors-on-user-kind = denTest (
      { den, tuxHm, ... }:
      {
        den.policies.s2-marker-c = _: [
          (den.lib.policy.include {
            homeManager.home.sessionVariables.S2_MARKER_C = "yes";
          })
        ];
        den.hosts.x86_64-linux.igloo.users.tux.aspect.includes = [ den.policies.s2-marker-c ];
        den.schema.user.excludes = [ "s2-marker-c" ];

        expr = tuxHm.home.sessionVariables or { };
        expectedError = {
          type = "ThrownError";
          msg = "den: den.schema.<kind>.excludes";
        };
      }
    );

    # A list-wrapped policy reference excludes at the ASPECT tier as of
    # 6127cbc, so it must not throw at the schema tier: `providerType` names a
    # list of policy records as a valid element, and the two tiers take the
    # same references. The schema-tier check had no list arm and rejected the
    # shape its sibling tier had just been fixed to honour.
    test-schema-excludes-list-wrapped-record-fires = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.policies.s2-marker-d = _: [
          (den.lib.policy.include {
            nixos.environment.variables.S2_MARKER_D = "yes";
          })
        ];
        den.aspects.igloo.includes = [ den.policies.s2-marker-d ];
        den.schema.host.excludes = [ [ den.policies.s2-marker-d ] ];

        expr = igloo.environment.variables.S2_MARKER_D or "absent";
        expected = "absent";
      }
    );

    # CONTROL for the cell above: the same policy with no exclude at all does
    # fire, so the "absent" there reads a suppression rather than a policy
    # that never delivered.
    test-schema-excludes-list-control-unexcluded-fires = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.policies.s2-marker-e = _: [
          (den.lib.policy.include {
            nixos.environment.variables.S2_MARKER_E = "yes";
          })
        ];
        den.aspects.igloo.includes = [ den.policies.s2-marker-e ];

        expr = igloo.environment.variables.S2_MARKER_E or "absent";
        expected = "yes";
      }
    );

    # A bad leaf at depth is still caught, with the den: message rather than
    # the raw Nix one — the list arm admits the shape without dropping the
    # check, matching the includes collection.
    test-schema-excludes-nested-string-still-errors = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.schema.host.excludes = [ [ "s2-marker-f" ] ];

        expr = igloo.networking.hostName;
        expectedError = {
          type = "ThrownError";
          msg = "den: den.schema.<kind>.excludes";
        };
      }
    );
  };
}
