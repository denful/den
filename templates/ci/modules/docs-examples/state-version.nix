# The example in docs/src/content/docs/guides/configure-aspects.mdx
# ("`stateVersion`: fleet-wide or per host").
{ denTest, lib, ... }:
{
  flake.tests.docs-state-version = {
    test-fleet-default-applies = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.nixos.system.stateVersion = lib.mkDefault "25.11";
        expr = igloo.system.stateVersion;
        expected = "25.11";
      }
    );
    test-host-pins-its-own = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.nixos.system.stateVersion = lib.mkDefault "25.11";
        den.aspects.igloo.nixos.system.stateVersion = "23.11";
        expr = igloo.system.stateVersion;
        expected = "23.11";
      }
    );
  };
}
