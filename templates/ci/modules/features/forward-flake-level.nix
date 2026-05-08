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

    # Parametric packages from user includes roll up to flake output.
    # The { host }: wrapper resolves per-host at user scope; the
    # to-packages route collects from the flake-system subtree.
    test-parametric-packages-from-user-includes = denTest (
      {
        den,
        lib,
        config,
        inputs,
        ...
      }:
      {
        imports = [ inputs.den.flakeOutputs.packages ];

        den.hosts.x86_64-linux.alpha.users.a = { };
        den.hosts.aarch64-linux.beta.users.b = { };

        den.aspects.a.includes = [ den.aspects.nh-tool ];
        den.aspects.b.includes = [ den.aspects.nh-tool ];

        den.aspects.nh-tool = {
          packages =
            { host }:
            { pkgs, ... }:
            {
              "sw-${host.name}" = pkgs.writeText "sw-${host.name}" host.name;
            };
        };

        expr = {
          alpha = config.flake.packages.x86_64-linux ? sw-alpha;
          beta = config.flake.packages.aarch64-linux ? sw-beta;
        };
        expected = {
          alpha = true;
          beta = true;
        };
      }
    );

    # Route with instantiate: collect class modules, call a function,
    # place the derivation at the target path.
    test-route-with-instantiate = denTest (
      {
        den,
        lib,
        config,
        inputs,
        ...
      }:
      {
        imports = [ inputs.den.flakeOutputs.packages ];

        den.hosts.x86_64-linux.alpha = { };
        den.hosts.x86_64-linux.beta = { };

        den.classes.infra = { };

        den.aspects.alpha.infra =
          { host, ... }:
          {
            ${host.name}.type = "small";
          };
        den.aspects.beta.infra =
          { host, ... }:
          {
            ${host.name}.type = "large";
          };

        # Route that collects infra class and instantiates via evalModules.
        den.policies.infra-to-packages =
          { system, ... }:
          [
            (den.lib.policy.route {
              fromClass = "infra";
              intoClass = "flake";
              path = [
                "flake"
                "packages"
                system
                "infra"
              ];
              instantiate =
                { modules, ... }:
                let
                  evaled =
                    (lib.evalModules {
                      modules = [
                        { config._module.freeformType = lib.types.lazyAttrsOf lib.types.raw; }
                      ]
                      ++ modules;
                    }).config;
                in
                builtins.removeAttrs evaled [ "_module" ];
            })
          ];

        den.schema.flake-system.includes = [ den.policies.infra-to-packages ];

        expr = config.flake.packages.x86_64-linux.infra;
        expected.alpha.type = "small";
        expected.beta.type = "large";
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
