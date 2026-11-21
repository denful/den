# The aspect-settings guide (docs/src/content/docs/guides/aspect-settings.mdx),
# on the builtin `den.lib.aspects.settingsType`.
{ denTest, lib, ... }:
let
  settingsOption = den: {
    options.settings = lib.mkOption {
      type = den.lib.aspects.settingsType;
      default = { };
    };
  };
  withSettings =
    { den, ... }:
    {
      den.reservedKeys = [ "settings" ];
      den.schema.host.imports = [ (settingsOption den) ];
    };
  awesome =
    { den, ... }:
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

    # One namespace on two entity kinds: the same declaration reads as
    # host.settings.<path> and user.settings.<path>.
    test-settings-on-two-entity-kinds = denTest (
      {
        den,
        config,
        igloo,
        ...
      }:
      {
        imports = [ withSettings ];
        den.schema.user.imports = [ (settingsOption den) ];
        den.aspects.shell.settings.prompt = lib.mkOption {
          type = lib.types.str;
          default = "$";
        };
        den.aspects.shell.nixos =
          { host, ... }:
          {
            environment.variables.HOST_PROMPT = host.settings.shell.prompt;
          };
        den.aspects.igloo.includes = [ den.aspects.shell ];
        den.hosts.x86_64-linux.igloo = {
          settings.shell.prompt = "host>";
          users.tux.settings.shell.prompt = "tux>";
        };
        expr = {
          inherit (igloo.environment.variables) HOST_PROMPT;
          USER_PROMPT = config.den.hosts.x86_64-linux.igloo.users.tux.settings.shell.prompt;
        };
        expected = {
          HOST_PROMPT = "host>";
          USER_PROMPT = "tux>";
        };
      }
    );

    # Built node by node, forcing class content no deeper than its top level:
    # content below it may read settings (or throw) without the settings tree
    # recursing into it.
    test-lazy-per-node = denTest (
      {
        den,
        config,
        igloo,
        ...
      }:
      {
        imports = [ withSettings ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.unused.nixos.environment = throw "class content forced while building settings";
        den.aspects.reads.nixos.environment.variables.READS =
          lib.boolToString config.den.hosts.x86_64-linux.igloo.settings.feature.enable;
        den.aspects.feature.settings.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        den.aspects.igloo.includes = [
          den.aspects.reads
          (
            { host, ... }:
            {
              nixos.environment.variables.FEATURE = lib.boolToString host.settings.feature.enable;
            }
          )
        ];
        den.hosts.x86_64-linux.igloo.settings.feature.enable = true;
        expr = {
          inherit (igloo.environment.variables) FEATURE READS;
        };
        expected = {
          FEATURE = "true";
          READS = "true";
        };
      }
    );

    # A functionTo setting shares one definition between the aspects that read it.
    test-function-to-setting = denTest (
      { den, igloo, ... }:
      {
        imports = [ withSettings ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.greeter.settings.greet = lib.mkOption {
          type = lib.types.functionTo lib.types.str;
          default = name: "hello ${name}";
        };
        den.aspects.igloo.includes = [
          (
            { host, ... }:
            {
              nixos.environment.variables.GREETING = host.settings.greeter.greet host.name;
            }
          )
        ];
        expr = igloo.environment.variables.GREETING;
        expected = "hello igloo";
      }
    );

    test-unreserved-settings-key-is-loud = denTest (
      { den, igloo, ... }:
      {
        den.schema.host.imports = [ (settingsOption den) ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feature.settings.enable = lib.mkOption { type = lib.types.bool; };
        den.aspects.igloo.includes = [
          (
            { host, ... }:
            {
              nixos.environment.variables.X = lib.boolToString host.settings.feature.enable;
            }
          )
        ];
        expectedError = {
          type = "ThrownError";
          msg = "add `den.reservedKeys";
        };
        expr = igloo.environment.variables.X;
      }
    );
  };
}
