{ denTest, ... }:
{
  flake.tests.excludes-string-form-rejected = {

    # D2: `excludes` used to accept a bare string with `lib.types.unspecified`
    # and silently exclude nothing (`identity.key` on a string yields
    # "<anon>", which matches no policy). `includes` already rejects a bare
    # string via `providerType`'s check; `excludes` must error the same way.
    test-excludes-string-form-errors = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.excludes = [ "some-name" ];

        expr = igloo.networking.hostName;
        expectedError = {
          type = "ThrownError";
          msg = "is not of type `aspect or function returning aspect'";
        };
      }
    );

    # Uncontested-policy control: a legitimate record-form exclude must still
    # fire, so the cell above isn't vacuous (everything erroring would look
    # identical to the fix working).
    test-excludes-record-form-still-fires = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.d2-marker = _: [
          (den.lib.policy.include {
            nixos.environment.variables.D2_MARKER = "yes";
          })
        ];
        den.aspects.igloo = {
          includes = [ den.policies.d2-marker ];
          excludes = [ den.policies.d2-marker ];
        };

        expr = igloo.environment.variables.D2_MARKER or "absent";
        expected = "absent";
      }
    );
  };
}
