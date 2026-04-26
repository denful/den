{ denTest, ... }:
{
  flake.tests.ctx-compat = {

    test-ctx-shim-forwards-to-stages = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.ctx.host = {
          nixos.networking.hostName = "from-ctx-shim";
        };

        expr = igloo.networking.hostName;
        expected = "from-ctx-shim";
      }
    );

    test-ctx-shim-includes = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.ctx.host.includes = [
          { nixos.users.users.tux.description = "from-ctx-include"; }
        ];

        expr = igloo.users.users.tux.description;
        expected = "from-ctx-include";
      }
    );

    # Manual into replaced by policy — den.ctx.*.into is no longer supported.
    test-ctx-shim-into = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.entityIncludes.test-into-target = [ ];

        den.policies.host-to-into-target = {
          from = "host";
          to = "test-into-target";
          resolve = _: [ { } ];
          aspects = [
            { nixos.users.users.tux.description = "from-into-target"; }
          ];
        };
        den.default.policies = [ "host-to-into-target" ];

        expr = igloo.users.users.tux.description;
        expected = "from-into-target";
      }
    );

  };
}
