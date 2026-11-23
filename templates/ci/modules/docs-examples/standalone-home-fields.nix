# The examples in docs/src/content/docs/guides/standalone-home-manager.mdx
# ("Your own fields on a home"). `gui` appends to a list, so a double include
# would count 2.
{ denTest, ... }:
let
  count = hm: builtins.length (builtins.filter (p: p == "gui") hm.home.sessionPath);
  hc = config: n: config.flake.homeConfigurations.${n}.config;
  base =
    { den, ... }:
    {
      den.default.homeManager.home.stateVersion = "25.11";
      den.default.includes = [ den._.define-user ];
      den.aspects.gui.homeManager.home.sessionPath = [ "gui" ];
    };
  shared =
    { den, lib, ... }:
    {
      imports = [ base ];
      den.schema.conf.options.isGraphical = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      den.aspects.tux.includes = [
        (
          { host, user, ... }:
          lib.optionalAttrs (host.isGraphical or false) { includes = [ den.aspects.gui ]; }
        )
        ({ home, ... }: lib.optionalAttrs home.isGraphical { includes = [ den.aspects.gui ]; })
      ];
    };
in
{
  flake.tests.docs-standalone-home-fields = {
    test-freeform-field-via-home = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        imports = [ base ];
        den.homes.x86_64-linux.tux.isGraphical = true;
        den.aspects.tux.includes = [
          ({ home, ... }: lib.optionalAttrs home.isGraphical { includes = [ den.aspects.gui ]; })
        ];
        expr = count (hc config "tux");
        expected = 1;
      }
    );
    test-shared-host-user = denTest (
      { igloo, ... }:
      {
        imports = [ shared ];
        den.hosts.x86_64-linux.igloo = {
          isGraphical = true;
          users.tux = { };
        };
        den.homes.x86_64-linux."tux@work".isGraphical = true;
        expr = count igloo.home-manager.users.tux;
        expected = 1;
      }
    );
    test-shared-standalone-home = denTest (
      { config, ... }:
      {
        imports = [ shared ];
        den.hosts.x86_64-linux.igloo = {
          isGraphical = true;
          users.tux = { };
        };
        den.homes.x86_64-linux."tux@work".isGraphical = true;
        expr = count (hc config "tux@work");
        expected = 1;
      }
    );
    test-shared-plain-home-off = denTest (
      { config, ... }:
      {
        imports = [ shared ];
        den.homes.x86_64-linux.tux = { };
        expr = count (hc config "tux");
        expected = 0;
      }
    );
    test-declared-host-both-flags-once = denTest (
      { config, ... }:
      {
        imports = [ shared ];
        den.hosts.x86_64-linux.igloo = {
          isGraphical = true;
          users.tux.classes = [ "user" ];
        };
        den.homes.x86_64-linux."tux@igloo".isGraphical = true;
        expr = count (hc config "tux@igloo");
        expected = 1;
      }
    );
    test-declared-host-flag-only = denTest (
      { config, ... }:
      {
        imports = [ shared ];
        den.hosts.x86_64-linux.igloo = {
          isGraphical = true;
          users.tux.classes = [ "user" ];
        };
        den.homes.x86_64-linux."tux@igloo" = { };
        expr = count (hc config "tux@igloo");
        expected = 1;
      }
    );
    test-declared-host-neither-flag = denTest (
      { config, ... }:
      {
        imports = [ shared ];
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "user" ];
        den.homes.x86_64-linux."tux@igloo" = { };
        expr = count (hc config "tux@igloo");
        expected = 0;
      }
    );
    # control: two distinct aspects each add "gui"; the counter must see both
    test-control-counter-reads-two = denTest (
      { den, config, ... }:
      {
        imports = [ shared ];
        den.aspects.gui2.homeManager.home.sessionPath = [ "gui" ];
        den.aspects.tux.includes = [ den.aspects.gui2 ];
        den.homes.x86_64-linux.tux.isGraphical = true;
        expr = count (hc config "tux");
        expected = 2;
      }
    );
  };
}
