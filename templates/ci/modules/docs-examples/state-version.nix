# The examples in docs/src/content/docs/guides/configure-aspects.mdx
# ("`stateVersion`: fleet-wide or per host").
{ denTest, lib, ... }:
let
  requiredPerHost = {
    den.schema.host =
      { lib, ... }:
      {
        options.stateVersion = lib.mkOption { type = lib.types.str; };
      };
    den.default.includes = [
      (
        { host, ... }:
        {
          nixos.system.stateVersion = host.stateVersion;
        }
      )
    ];
  };
in
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
    test-required-per-host-set = denTest (
      { den, igloo, ... }:
      {
        imports = [ requiredPerHost ];
        den.hosts.x86_64-linux.igloo = {
          stateVersion = "24.11";
          users.tux = { };
        };
        expr = igloo.system.stateVersion;
        expected = "24.11";
      }
    );
    test-required-per-host-missing = denTest (
      { den, igloo, ... }:
      {
        imports = [ requiredPerHost ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        expectedError = {
          type = "ThrownError";
          msg = "igloo.stateVersion' is used but not defined";
        };
        expr = igloo.system.stateVersion;
      }
    );
  };
}
