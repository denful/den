{ den, lib, ... }:
{
  options.den.default = lib.mkOption {
    description = "Default aspect";
    type = den.lib.aspects.types.aspectType;
  };
  # Default aspect stored as entityIncludes for the "default" entity.
  # Pipeline resolves this when den.entityIncludes.default exists.
  config.den.entityIncludes.default = [ den.default ];
}
