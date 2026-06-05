{ denTest, ... }:
{
  flake.tests.import-tree = {

    test-host-auto-import = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.rockhopper.users.tux = { };
        den.default.includes = [
          (den.provides.import-tree.provides.host ../../non-dendritic/hosts)
        ];

        expr = config.flake.nixosConfigurations.rockhopper.config.auto-imported;
        expected = true;
      }
    );

    test-no-import-for-missing-dir = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [
          (den.provides.import-tree ../../non-dendritic/no-such-dir)
        ];

        expr = igloo ? auto-imported;
        expected = false;
      }
    );

  };
}
