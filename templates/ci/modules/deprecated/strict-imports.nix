{ denTest, lib, ... }:
{
  flake.tests.strict-imports = {
    test-host = denTest (
      { den, ... }:
      {
        den.schema.host.imports = [ den.lib.strict ];
        den.hosts.x86_64-linux.igloo.arbitrary = "value";

        expr = den.hosts.x86_64-linux.igloo.arbitrary;
        expectedError = {
          type = "ThrownError";
          msg = "STRICT MODE: \"arbitrary\" is not declared on host .instance at den.hosts.x86_64-linux.igloo,";
        };
      }
    );

    test-host-declared-option = denTest (
      { den, ... }:
      {
        den.schema.host.imports = [
          den.lib.strict
          { options.arbitrary = lib.mkOption { type = lib.types.str; }; }
        ];
        den.hosts.x86_64-linux.igloo.arbitrary = "value";

        expr = den.hosts.x86_64-linux.igloo.arbitrary;
        expected = "value";
      }
    );

    test-host-evaluates = denTest (
      { den, igloo, ... }:
      {
        den.schema.host.imports = [ den.lib.strict ];
        den.schema.user.imports = [ den.lib.strict ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos.networking.hostName = "strict";

        expr = igloo.networking.hostName;
        expected = "strict";
      }
    );

    test-aspect = denTest (
      { den, ... }:
      {
        den.schema.aspect.imports = [ den.lib.strict ];
        den.aspects.test.arbitrary = "value";

        expr = den.aspects.test.arbitrary;
        expectedError = {
          type = "ThrownError";
          msg = "STRICT MODE: \"arbitrary\" is not declared on aspect .instance at den.aspects.test,";
        };
      }
    );

    test-flake = denTest (
      { den, config, ... }:
      {
        den.schema.flake.imports = [ den.lib.strict ];
        flake.arbitrary = "value";

        expr = config.flake.arbitrary;
        expectedError = {
          type = "ThrownError";
          msg = "The option `flake.arbitrary' does not exist";
        };
      }
    );
  };

  flake.tests.mkInstanceType-kind-first = {
    test-kind-first = denTest (
      { den, ... }:
      let
        t = den.lib.schema.mkInstanceType den.schema.conf {
          strict = false;
          extraModules = [ { options.foo = lib.mkOption { default = "bar"; }; } ];
        };
      in
      {
        expr =
          (lib.evalModules {
            modules = [
              { options.x = lib.mkOption { type = t; }; }
              { x = { }; }
            ];
          }).config.x.foo;
        expected = "bar";
      }
    );
  };
}
