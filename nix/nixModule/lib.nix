{ lib, den-lib, ... }:
{
  config.den.lib = den-lib;
  options.den.lib = lib.mkOption {
    internal = true;
    visible = false;
    type = lib.types.submodule { freeformType = lib.types.lazyAttrsOf lib.types.unspecified; };
  };
}
