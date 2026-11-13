# Regression: a module reading `lib` in an `extraModules` entry of
# `den.lib.schema.mkInstanceRegistry` was refused, because only
# `mkInstanceType` supplied `lib`. Reported in GitHub #766.
{ denTest, ... }:
let
  hostOpt =
    { lib, ... }:
    {
      options.backendKind = lib.mkOption {
        type = lib.types.enum [
          "container"
          "node"
        ];
        default = "node";
      };
    };
  registry =
    den: opts:
    den.lib.schema.mkInstanceRegistry (
      {
        strict = den.schema.host.isStrict;
        extraModules = [ hostOpt ];
      }
      // opts
    ) den.schema.host;
  eval =
    lib: option:
    (lib.evalModules {
      modules = [
        { options.denHosts = option; }
        { denHosts.machine = { }; }
      ];
    }).config.denHosts.machine;
in
{
  flake.tests.instance-registry-lib = {
    test-registry-module-reads-lib = denTest (
      { den, lib, ... }:
      {
        expr = (eval lib (registry den { })).backendKind;
        expected = "node";
      }
    );
    test-registry-instance-name = denTest (
      { den, lib, ... }:
      {
        expr = (eval lib (registry den { })).name;
        expected = "machine";
      }
    );
    # A caller's own `specialArgs` still reach the module.
    test-registry-caller-specialargs = denTest (
      { den, lib, ... }:
      let
        reads = {
          options.marker = lib.mkOption { default = null; };
        };
        withMarker =
          { marker, ... }:
          {
            options.seen = lib.mkOption { default = marker; };
          };
      in
      {
        expr =
          (eval lib (
            registry den {
              specialArgs.marker = "caller";
              extraModules = [
                hostOpt
                reads
                withMarker
              ];
            }
          )).seen;
        expected = "caller";
      }
    );
  };
}
