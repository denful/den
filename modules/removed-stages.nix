{ lib, ... }:
{
  options.den.stages = lib.mkOption {
    visible = false;
    internal = true;
    type = lib.types.raw;
    apply =
      _:
      throw ''
        den.stages has been removed. Migrate to:
          den.schema.<kind>.includes = [ ... ];  (replaces den.stages.<kind>.includes)
        For providers, use policy.aspects with direct aspect references.
      '';
    default = { };
  };
}
