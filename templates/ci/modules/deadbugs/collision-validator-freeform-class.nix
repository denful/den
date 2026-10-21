# Regression: a class module taking a den context arg and a module-system arg
# (`{ host, lib, ... }:`) is paired with a collision validator that defines
# `warnings`. In a target with a freeformType and no `warnings` option, that
# definition became freeform data whose merge forced the collision check, which
# read `config._module.args` and so needed the config being merged (infinite
# recursion).
{ denTest, lib, ... }:
let
  # Capture igloo's `settings` class modules into flake.settingsModules.igloo.
  capture =
    { den, ... }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.classes.settings.description = "settings fragments";
      den.policies.settings-capture =
        { host, ... }:
        [
          (den.lib.policy.instantiate {
            name = "${host.name}-settings";
            class = "settings";
            instantiate = { modules, ... }: modules;
            intoAttr = [
              "settingsModules"
              host.name
            ];
          })
        ];
      den.schema.host.includes = [ den.policies.settings-capture ];
      # `lib` is a module-system arg, so the module keeps an arg to forward
      # and is paired with a collision validator.
      den.aspects.igloo.settings =
        { host, lib, ... }:
        {
          hostName = lib.toUpper host.name;
        };
    };

  evalWith =
    extraModule: modules:
    (lib.evalModules {
      modules = modules ++ [ extraModule ];
    }).config;
in
{
  flake.tests.deadbugs.collision-validator-freeform-class = {

    test-freeform-target-without-warnings = denTest (
      { config, ... }:
      {
        imports = [ capture ];
        expr =
          (evalWith {
            freeformType = lib.types.attrsOf lib.types.anything;
          } config.flake.settingsModules.igloo).hostName;
        expected = "IGLOO";
      }
    );

    # Nothing to report: no `warnings` lands in the freeform data.
    test-freeform-target-gets-no-warnings-data = denTest (
      { config, ... }:
      {
        imports = [ capture ];
        expr =
          (evalWith {
            freeformType = lib.types.attrsOf lib.types.anything;
          } config.flake.settingsModules.igloo) ? warnings;
        expected = false;
      }
    );

    # A collision under the default "error" policy still throws in a freeform
    # target without a `warnings` option.
    test-freeform-target-collision-error-throws = denTest (
      { config, ... }:
      {
        imports = [ capture ];
        expr =
          (builtins.tryEval (
            builtins.deepSeq (evalWith {
              freeformType = lib.types.attrsOf lib.types.anything;
              config._module.args.host = "from-module-system";
            } config.flake.settingsModules.igloo) null
          )).success;
        expected = false;
      }
    );

    # A non-error collision is reported as an eval warning there, not as data.
    test-freeform-target-collision-den-wins = denTest (
      { config, ... }:
      {
        imports = [ capture ];
        den.schema.host.collisionPolicy = "den-wins";
        expr =
          let
            cfg = evalWith {
              freeformType = lib.types.attrsOf lib.types.anything;
              config._module.args.host = "from-module-system";
            } config.flake.settingsModules.igloo;
          in
          {
            inherit (cfg) hostName;
            warnings = cfg ? warnings;
          };
        expected = {
          hostName = "IGLOO";
          warnings = false;
        };
      }
    );

    # A target that declares `warnings` still gets the collision report.
    test-target-with-warnings-reports-collision = denTest (
      { config, ... }:
      {
        imports = [ capture ];
        den.schema.host.collisionPolicy = "den-wins";
        expr =
          (evalWith {
            freeformType = lib.types.attrsOf lib.types.anything;
            options.warnings = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            config._module.args.host = "from-module-system";
          } config.flake.settingsModules.igloo).warnings;
        expected = [
          "den: class module arg 'host' collision — den-wins, module-system value shadowed"
        ];
      }
    );

  };
}
