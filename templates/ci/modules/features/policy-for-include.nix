{ denTest, ... }:
{
  flake.tests.policy-for-include = {
    # policy.for wrapping policy.include should work (was: "attempt to call
    # something which is not a function but a set").
    test-for-include-fires = denTest (
      { den, config, ... }:
      let
        inherit (den) aspects;
        inherit (den.lib) policy;
        yalova = den.hosts.x86_64-linux.yalova;
        yalovaConfig = config.flake.nixosConfigurations.yalova.config;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.yalova.users.tux = { };

        den.schema.host.includes = [
          (policy.for yalova (policy.include aspects.zed-editor))
        ];

        den.aspects.zed-editor = {
          nixos.networking.hostName = "from-zed";
        };

        expr = yalovaConfig.networking.hostName;
        expected = "from-zed";
      }
    );

    # policy.for on a non-matching entity should suppress the include.
    test-for-include-suppressed = denTest (
      { den, igloo, ... }:
      let
        inherit (den) aspects;
        inherit (den.lib) policy;
        yalova = den.hosts.x86_64-linux.yalova;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.yalova.users.tux = { };

        den.schema.host.includes = [
          (policy.for yalova (policy.include aspects.zed-editor))
        ];

        den.aspects.zed-editor = {
          nixos.services.foobar.enable = true;
        };

        expr = igloo.services.foobar.enable or false;
        expected = false;
      }
    );

    # policy.when wrapping policy.include should work.
    test-when-include-fires = denTest (
      { den, igloo, ... }:
      let
        inherit (den) aspects;
        inherit (den.lib) policy;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.host.includes = [
          (policy.when (_: true) (policy.include aspects.zed-editor))
        ];

        den.aspects.zed-editor = {
          nixos.networking.hostName = "from-zed";
        };

        expr = igloo.networking.hostName;
        expected = "from-zed";
      }
    );

    # policy.when wrapping an inline aspect attrset should work.
    test-when-inline-aspect = denTest (
      { den, igloo, ... }:
      let
        inherit (den.lib) policy;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.host.includes = [
          (policy.when (_: true) {
            nixos.networking.hostName = "from-inline";
          })
        ];

        expr = igloo.networking.hostName;
        expected = "from-inline";
      }
    );
  };
}
