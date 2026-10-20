denGen:
let
  # flake-parts already declares `flake`, so only the plain-evalModules host adds it.
  mk =
    declareFlake:
    { lib, config, inputs, ... }:
    {
      options =
        lib.optionalAttrs declareFlake {
          flake = lib.mkOption {
            type = lib.types.lazyAttrsOf lib.types.raw;
            default = { };
          };
        }
        // {
          den = lib.mkOption {
            type = lib.types.deferredModule;
            default = { };
          };
        };
      config._module.args.den = denGen.evalDen config.den;
      config.flake.nixosConfigurations = denGen.hosts config._module.args.den inputs;
    };
in
{
  flakeModule = mk true;
  flakeModules.default = mk false;
}
