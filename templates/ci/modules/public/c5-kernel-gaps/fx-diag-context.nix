# Tests for the diag library's capture integration.
#
# Context graph construction tests (basic context, exclude handling) live
# in den-diagram's own test suite. These tests exercise den-specific capture
# and constraint APIs that require the full pipeline.
{
  denTest,
  lib,
  ...
}:
{
  flake.tests.fx-diag-context = {

    test-capture-in-context = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.testhost.users.tux = { };
        den.aspects.testhost.nixos =
          { ... }:
          {
            networking.hostName = "test";
          };
        den.aspects.testhost.includes = [
          den.aspects.networking
        ];
        den.aspects.networking.nixos =
          { ... }:
          {
            networking.firewall.enable = true;
          };
        expr =
          let
            host = lib.head (builtins.attrValues den.hosts.x86_64-linux);
            root = den.lib.resolveEntity "host" { inherit host; };
            result = den.lib.capture.captureWithPaths [ "nixos" ] root;
          in
          {
            hasEntries = (builtins.length result.entries) > 0;
            hasPathsByClass = result.pathsByClass ? nixos;
          };
        expected = {
          hasEntries = true;
          hasPathsByClass = true;
        };
      }
    );

    test-fx-constraints-access = denTest (
      { den, ... }:
      let
        excludeDecl = den.lib.aspects.fx.constraints.exclude {
          name = "drop";
          meta.aspect-chain = [ ];
        };
      in
      {
        expr = excludeDecl.type;
        expected = "exclude";
      }
    );

  };
}
