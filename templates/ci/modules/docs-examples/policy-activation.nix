# The example in docs/src/content/docs/explanation/policy-activation.mdx
# ("Where a policy reaches, and how often it fires").
{ denTest, lib, ... }:
{
  flake.tests.docs-policy-activation = {
    test-per-user-instance-once-each = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.policies.per-user =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              receiver = host;
              module.boot.kernelModules = [ "u-${user.name}" ];
            })
          ];
        den.schema.host.includes = [ den.policies.per-user ];
        expr = lib.sort lib.lessThan (builtins.filter (lib.hasPrefix "u-") igloo.boot.kernelModules);
        expected = [
          "u-pingu"
          "u-tux"
        ];
      }
    );
  };
}
