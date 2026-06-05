{ denTest, ... }:
{
  flake.tests.doc-examples = {

    # migrate-ctx.mdx: compat shim forwards den.ctx class keys to den.stages.
    test-doc-ctx-class-shim = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.ctx.host = {
          nixos.networking.hostName = "shim-igloo";
        };

        expr = igloo.networking.hostName;
        expected = "shim-igloo";
      }
    );

  };
}
