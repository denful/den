{ denTest, ... }:
{
  flake.tests.issue-687-schema-module-lib-arg = {
    # the reporter's shape: a schema module whose BODY is `lib.mkIf …`,
    # with `lib` taken as a module argument
    test-lib-arg-mkif-body = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.schema.host =
          { lib, config, ... }:
          lib.mkIf (config.class == "nixos") {
            hostName = lib.mkForce "gated";
          };
        expr = den.hosts.x86_64-linux.igloo.hostName;
        expected = "gated";
      }
    );

    # control: same module, `lib` forced only inside a lazy position
    test-lib-arg-mkif-inner = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.schema.host =
          { lib, config, ... }:
          {
            hostName = lib.mkIf (config.class == "nixos") (lib.mkForce "gated");
          };
        expr = den.hosts.x86_64-linux.igloo.hostName;
        expected = "gated";
      }
    );

    # SECOND ARM. No instance exists, so `mkInstanceType` is not on this path
    # at all: the kind's own option tree recurses. Measured 2026-09-21, so a
    # fix threaded only through the instance constructor leaves this red.
    test-lib-arg-uninstantiated-kind = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.schema.fleet = { lib, ... }: lib.mkIf true { };
        expr = builtins.isAttrs den.schema.fleet.options;
        expected = true;
      }
    );

    # THE CONTROL FOR THE CELL ABOVE, and it stays in the suite rather than
    # being run once and discarded. `den.schema._kindNames` does NOT force a
    # kind's modules, so an earlier version of that cell passed while proving
    # nothing. This one fails the moment the forcing expression stops forcing.
    test-uninstantiated-kind-is-forced = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.schema.fleet = { ... }: throw "DEN687-FLEET-FORCED";
        expr = builtins.isAttrs den.schema.fleet.options;
        expectedError = {
          type = "ThrownError";
          msg = "DEN687-FLEET-FORCED";
        };
      }
    );
  };
}
