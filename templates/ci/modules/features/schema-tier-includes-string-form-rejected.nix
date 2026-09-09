# `den.schema.<kind>.includes` used to accept a bare string (or any
# non-aspect value) and reach `children.nix`'s aspect walk unchecked,
# crashing with a raw Nix `expected a set but found a string` from
# `propagateScope`'s `//` — gen-schema has no per-collection `type` for this
# untyped collection to route the bad value through first. See
# `schema-tier-excludes-string-form-rejected.nix` for the sibling `excludes`
# fix this mirrors.
{ denTest, ... }:
{
  flake.tests.schema-tier-includes-string-form-rejected = {

    test-schema-includes-string-form-errors = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.includes = [ "s3-marker" ];

        expr = igloo.networking.hostName;
        expectedError = {
          type = "ThrownError";
          msg = "den: den.schema.<kind>.includes";
        };
      }
    );

    # Uncontested-policy control: a legitimate aspect/policy-form include
    # must still fire, so the cell above isn't vacuous (everything erroring
    # would look identical to the fix working).
    test-schema-includes-record-form-still-fires = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.s3marker.nixos.environment.variables.S3_MARKER = "yes";
        den.schema.host.includes = [ den.aspects.s3marker ];

        expr = igloo.environment.variables.S3_MARKER or "absent";
        expected = "yes";
      }
    );

    # Nested-list leaf: children.nix's processInclude walks nested lists,
    # so a bad leaf below the top level must still be caught, not silently
    # reach the raw crash a level deeper.
    test-schema-includes-nested-string-form-errors = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.includes = [ [ "s3-marker-nested" ] ];

        expr = igloo.networking.hostName;
        expectedError = {
          type = "ThrownError";
          msg = "den: den.schema.<kind>.includes";
        };
      }
    );

    # Breadth: the defect reaches every schema kind, not just `host`.
    test-schema-includes-string-form-errors-on-user-kind = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.aspect.includes = [ ];
        den.schema.user.includes = [ "s3-marker-user" ];

        expr = tuxHm.home.sessionVariables or { };
        expectedError = {
          type = "ThrownError";
          msg = "den: den.schema.<kind>.includes";
        };
      }
    );
  };
}
