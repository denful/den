# The `_settings-type.nix` generator in docs/src/content/docs/guides/aspect-settings.mdx.
{ denTest, lib, ... }:
let
  withSettings =
    { den, lib, ... }:
    {
      den.reservedKeys = [ "settings" ];
      den.schema.host.imports = [
        {
          options.settings = lib.mkOption {
            type = import ./_settings-type.nix { inherit den lib; };
            default = { };
          };
        }
      ];
    };
  awesome =
    { den, lib, ... }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.aspects.my.awesome-aspect = {
        settings.something = lib.mkOption { type = lib.types.str; };
        nixos =
          { host, ... }:
          {
            environment.variables.TEST_SETTINGS = host.settings.my.awesome-aspect.something;
          };
      };
      den.aspects.igloo.includes = [ den.aspects.my.awesome-aspect ];
      den.hosts.x86_64-linux.igloo.settings.my.awesome-aspect.something = "The Penguin";
    };
in
{
  flake.tests.docs-aspect-settings = {
    test-nested-settings = denTest (
      { igloo, ... }:
      {
        imports = [
          withSettings
          awesome
        ];
        expr = igloo.environment.variables.TEST_SETTINGS;
        expected = "The Penguin";
      }
    );

    # Discussion #776: a quirk named like a top-level aspect.
    test-quirk-named-like-top-level-aspect = denTest (
      { igloo, ... }:
      {
        imports = [
          withSettings
          awesome
        ];
        den.quirks.my.description = "a quirk sharing a top-level aspect's name";
        expr = igloo.environment.variables.TEST_SETTINGS;
        expected = "The Penguin";
      }
    );

    test-nested-collision-names-aspect-and-quirk = denTest (
      { den, igloo, ... }:
      {
        imports = [ withSettings ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.crds.description = "a quirk sharing a nested aspect's name";
        den.aspects.services.foo.crds.settings.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        den.aspects.services.foo.crds.nixos =
          { host, ... }:
          {
            environment.variables.CRDS = lib.boolToString host.settings.services.foo.crds.enable;
          };
        den.aspects.igloo.includes = [ den.aspects.services.foo.crds ];
        expectedError = {
          type = "ThrownError";
          msg = "aspect `services.foo.crds` declares settings, but `crds` is a registered quirk";
        };
        expr = igloo.environment.variables.CRDS;
      }
    );
  };
}
