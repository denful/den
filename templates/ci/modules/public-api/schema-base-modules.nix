# Copy this file to start new tests
{ denTest, ... }:
{
  flake.tests.schema-base-modules = {

    test-host-schema-module-args = denTest (
      { den, lib, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.schema.host =
          { host, ... }:
          {
            options.ok = lib.mkOption { default = true; };
          };
        expr = den.hosts.x86_64-linux.igloo.ok;
        expected = true;
      }
    );

    test-user-schema-module-args = denTest (
      { den, lib, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.user =
          { user, host, ... }:
          {
            # host can also be read from user.host
            options.ok = lib.mkOption { default = user ? host; };
          };
        expr = den.hosts.x86_64-linux.igloo.users.tux.ok;
        expected = true;
      }
    );

    test-home-bound-schema-module-args = denTest (
      { den, lib, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.homes.x86_64-linux."tux@igloo" = { };
        den.schema.home =
          { home, ... }:
          {
            # host and user can also be read from home
            options.ok = lib.mkOption { default = home ? host && home ? user; };
          };
        expr = den.homes.x86_64-linux."tux@igloo".ok;
        expected = true;
      }
    );

    test-host-base = denTest (
      { den, lib, ... }:
      {
        den.schema.host =
          { host, ... }:
          {
            options.vpn-alias = lib.mkOption { default = host.name; };
          };

        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = den.hosts.x86_64-linux.igloo.vpn-alias;
        expected = "igloo";
      }
    );

    test-user-base = denTest (
      { den, lib, ... }:
      {
        den.schema.user =
          { user, host, ... }:
          {
            options.main-group = lib.mkOption { default = user.name; };
            options.description = lib.mkOption { default = "${user.name}@${host.name}"; };
          };

        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = [
          den.hosts.x86_64-linux.igloo.users.tux.main-group
          den.hosts.x86_64-linux.igloo.users.tux.description
        ];
        expected = [
          "tux"
          "tux@igloo"
        ];
      }
    );

    test-home-base = denTest (
      { den, lib, ... }:
      {
        den.schema.home =
          { home, ... }:
          {
            options.main-group = lib.mkOption { default = home.name; };
          };

        den.homes.x86_64-linux.tux = { };

        expr = den.homes.x86_64-linux.tux.main-group;
        expected = "tux";
      }
    );

    test-conf-base = denTest (
      { den, lib, ... }:
      {
        den.schema.conf =
          { ... }:
          {
            options.foo = lib.mkOption { default = "foo"; };
          };

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.homes.x86_64-linux.tux = { };

        expr = [
          den.hosts.x86_64-linux.igloo.foo
          den.hosts.x86_64-linux.igloo.users.tux.foo
          den.homes.x86_64-linux.tux.foo
        ];
        expected = [
          "foo"
          "foo"
          "foo"
        ];
      }
    );

    test-user-nested-submodule = denTest (
      { den, lib, ... }:
      {
        den.schema.user =
          { user, host, ... }:
          {
            options.main-group = lib.mkOption { default = user.name; };
            options.description = lib.mkOption { default = "${user.name}@${host.name}"; };
            options.meta = lib.mkOption {
              type = lib.types.submodule (
                { ... }:
                {
                  options = {
                    email = lib.mkOption { type = lib.types.str; };
                    key = lib.mkOption { type = lib.types.str; };
                  };
                }
              );
            };
          };

        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = [
          den.hosts.x86_64-linux.igloo.users.tux.main-group
          den.hosts.x86_64-linux.igloo.users.tux.description
        ];
        expected = [
          "tux"
          "tux@igloo"
        ];
      }
    );

  };
}
