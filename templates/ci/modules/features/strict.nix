{ denTest, lib, ... }:
{
  flake.tests.strict-mode = {
    test-relaxed-mode = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux = { };

          arbitrary = "value";
        };

        expr = den.hosts.x86_64-linux.igloo.arbitrary;
        expected = "value";
      }
    );

    test-strict-mode-host = denTest (
      { den, ... }:
      {
        den.schema.host = den.lib.strict;

        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          arbitrary = "value";
        };

        expr = den.hosts.x86_64-linux.igloo.arbitrary;
        expectedError = {
          type = "ThrownError";
          msg = "Attempted to set the option \"arbitrary\" in \"den.hosts.x86_64-linux.igloo\"";
        };
      }
    );

    test-strict-mode-user = denTest (
      { den, ... }:
      {
        den.schema.user = den.lib.strict;

        den.hosts.x86_64-linux.igloo.users.tux.arbitrary = "value";

        expr = den.hosts.x86_64-linux.igloo.users.tux.arbitrary;
        expectedError = {
          type = "ThrownError";
          msg = "Attempted to set the option \"arbitrary\" in \"den.hosts.x86_64-linux.igloo.users.tux\"";
        };
      }
    );

    test-strict-mode-aspect = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.aspect = den.lib.strict;
        den.aspects.igloo.arbitrary = { };

        expr = den.aspects.igloo.arbitrary;
        expectedError = {
          type = "ThrownError";
          msg = "Attempted to set the option \"arbitrary\" in \"den.aspects.igloo\"";
        };
      }
    );

    test-strict-mode-flake = denTest (
      { den, config, ... }:
      {
        den.schema.flake = den.lib.strict;
        flake.arbitray = "value";

        expr = config.flake.arbitray;
        expectedError = {
          type = "ThrownError";
          msg = "Attempted to set the option \"arbitray\" in \"flake\"";
        };
      }
    );

    test-strict-mode-flake-customisable = denTest (
      { den, config, ... }:
      {
        den.schema.flake.imports = [
          den.lib.strict
          {
            options.arbitrary = lib.mkOption {
              type = lib.types.str;
            };
          }
        ];
        flake.arbitrary = "value";

        expr = config.flake.arbitrary;
        expected = "value";
      }
    );

    flakeModule.strict = {
      test-host = denTest (
        { inputs, den, ... }:
        {
          imports = [ inputs.den.flakeModules.strict ];

          den.hosts.x86_64-linux.igloo.arbitrary = "value";

          expr = den.hosts.x86_64-linux.igloo.arbitrary;
          expectedError = {
            type = "ThrownError";
            msg = "Attempted to set the option \"arbitrary\" in \"den.hosts.x86_64-linux.igloo\"";
          };
        }
      );

      test-user = denTest (
        { inputs, den, ... }:
        {
          imports = [ inputs.den.flakeModules.strict ];

          den.hosts.x86_64-linux.igloo.users.tux.arbitrary = "value";

          expr = den.hosts.x86_64-linux.igloo.users.tux.arbitrary;
          expectedError = {
            type = "ThrownError";
            msg = "Attempted to set the option \"arbitrary\" in \"den.hosts.x86_64-linux.igloo.users.tux\"";
          };
        }
      );

      test-aspect = denTest (
        { inputs, den, ... }:
        {
          imports = [ inputs.den.flakeModules.strict ];

          den.aspects.test.arbitrary = "value";

          expr = den.aspects.test.arbitrary;
          expectedError = {
            type = "ThrownError";
            msg = "Attempted to set the option \"arbitrary\" in \"den.aspects.test\"";
          };
        }
      );

      test-flake = denTest (
        { inputs, config, ... }:
        {
          imports = [ inputs.den.flakeModules.strict ];

          flake.arbitrary = "value";

          expr = config.flake.arbitrary;
          expectedError = {
            type = "ThrownError";
            msg = "STRICT MODE";
          };
        }
      );
    };
  };
}
