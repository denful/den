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
          fromAspect = item: den.lib.resolveStage "foo" item;
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

        den.stages.foo.provides.foo = { name }: den.aspects.${name};

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

    test-forward-flake-packages-from-aspect = denTest (
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

        den.stages.flake-packages.includes = [ den.aspects.igloo ];

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

    test-forward-flake-apps-from-aspect = denTest (
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

        den.aspects.foo = {
          apps =
            { pkgs, ... }:
            {
              inherit (pkgs) hello;
            };
        };

        den.stages.flake-apps.includes = [ den.aspects.foo ];

        expr = lib.getName config.flake.apps.x86_64-linux.hello;
        expected = "hello";
      }
    );

    test-forward-flake-checks-from-aspect = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        imports = [ inputs.den.flakeOutputs.checks ];
        den.hosts.x86_64-linux.igloo = { };

        den.aspects.foo = {
          checks =
            { pkgs, ... }:
            {
              inherit (pkgs) hello;
            };
        };

        den.stages.flake-checks.includes = [ den.aspects.foo ];

        expr = lib.getName config.flake.checks.x86_64-linux.hello;
        expected = "hello";
      }
    );

    test-forward-flake-devShells-from-aspect = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        imports = [ inputs.den.flakeOutputs.devShells ];
        den.hosts.x86_64-linux.igloo = { };

        den.aspects.foo = {
          devShells =
            { pkgs, ... }:
            {
              default = pkgs.mkShell {
                buildInputs = [ pkgs.hello ];
              };
            };
        };

        den.stages.flake-devShells.includes = [ den.aspects.foo ];

        expr = config.flake.devShells.x86_64-linux ? default;
        expected = true;
      }
    );

    test-forward-flake-outputs-from-hosts = denTest (
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

        den.policies.flake-system-to-host = {
          from = "flake-system";
          to = "host";
          resolve =
            ctx:
            if ctx ? system then
              map (host: { inherit host; }) (lib.attrValues den.hosts.${ctx.system})
            else
              [ ];
        };

        den.default.policies = [ "flake-system-to-host" ];

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
