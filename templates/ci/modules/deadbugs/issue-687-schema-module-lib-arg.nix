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
  };
}
