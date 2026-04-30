{ denTest, inputs, ... }:
{
  flake.tests.forward-flake-level = {

    test-forward-flake-foo = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      let
        fwd = den.provides.forward {
          each = [ { name = "moo"; } ];
          fromClass = item: "goofy";
          intoClass = _: "flake";
          intoPath = item: [
            "very"
            "funny"
          ];
          fromAspect = item: den.lib.resolveEntity "foo" item;
        };

        mod = den.lib.aspects.resolve "flake" fwd;

        outMod = {
          options.very.funny = lib.mkOption {
            type = lib.types.submodule {
              options.names = lib.mkOption {
                type = lib.types.listOf lib.types.str;
              };
            };
          };
        };
      in
      {

        den.schema.foo.includes = [ ({ name }: den.aspects.${name}) ];

        den.aspects.moo = {
          goofy.names = [ "hello" ];
        };

        expr =
          (lib.evalModules {
            modules = [
              outMod
              mod
            ];
          }).config;
        expected.very.funny.names = [ "hello" ];
      }
    );

    test-route-flake-packages-from-aspect = denTest (
      {
        den,
        lib,
        config,
        inputs,
        ...
      }:
      {
        imports = [ inputs.den.flakeOutputs.packages ];
        den.hosts.x86_64-linux.igloo = { };

        den.schema.flake-system.includes = [ den.aspects.igloo ];

        den.aspects.igloo = {
          packages =
            { pkgs, ... }:
            {
              inherit (pkgs) hello;
            };
        };

        expr = lib.getName config.flake.packages.x86_64-linux.hello;
        expected = "hello";
      }
    );

    test-route-flake-apps-from-aspect = denTest (
      {
        den,
        lib,
        config,
        inputs,
        ...
      }:
      {
        imports = [ inputs.den.flakeOutputs.apps ];
        den.hosts.x86_64-linux.igloo = { };

        den.schema.flake-system.includes = [ den.aspects.foo ];

        den.aspects.foo = {
          apps =
            { pkgs, ... }:
            {
              inherit (pkgs) hello;
            };
        };

        expr = lib.getName config.flake.apps.x86_64-linux.hello;
        expected = "hello";
      }
    );

    test-route-flake-checks-from-aspect = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        imports = [ inputs.den.flakeOutputs.checks ];
        den.hosts.x86_64-linux.igloo = { };

        den.schema.flake-system.includes = [ den.aspects.foo ];

        den.aspects.foo = {
          checks =
            { pkgs, ... }:
            {
              inherit (pkgs) hello;
            };
        };

        expr = lib.getName config.flake.checks.x86_64-linux.hello;
        expected = "hello";
      }
    );

    test-route-flake-devShells-from-aspect = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        imports = [ inputs.den.flakeOutputs.devShells ];
        den.hosts.x86_64-linux.igloo = { };

        den.schema.flake-system.includes = [ den.aspects.foo ];

        den.aspects.foo = {
          devShells =
            { pkgs, ... }:
            {
              default = pkgs.mkShell {
                buildInputs = [ pkgs.hello ];
              };
            };
        };

        expr = config.flake.devShells.x86_64-linux ? default;
        expected = true;
      }
    );

    test-route-flake-outputs-from-hosts = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        imports = with inputs.den.flakeOutputs; [
          packages
          checks
        ];
        den.hosts.x86_64-linux.igloo = { };

        den.schema.flake-system.includes = [ den.aspects.igloo ];

        den.aspects.igloo = {
          packages =
            { pkgs, ... }:
            {
              inherit (pkgs) hello;
            };
          checks =
            { pkgs, ... }:
            {
              inherit (pkgs) hello;
            };
        };

        expr = {
          package = lib.getName config.flake.packages.x86_64-linux.hello;
          check = lib.getName config.flake.checks.x86_64-linux.hello;
        };
        expected.package = "hello";
        expected.check = "hello";
      }
    );

  };
}
