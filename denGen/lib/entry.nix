denGen: {
  flakeModule =
    {
      lib,
      config,
      inputs,
      ...
    }:
    {
      options.flake = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.raw;
        default = { };
      };
      options.den = lib.mkOption {
        type = lib.types.deferredModule;
        default = { };
      };
      config._module.args.den = {
        batteries = { };
        lib = { };
      };
    };
}
