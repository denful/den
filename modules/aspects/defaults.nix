{ den, lib, ... }:
{
  options.den.default = lib.mkOption {
    description = "Default aspect";
    type = den.lib.aspects.types.aspectType;
  };

  # Inject den.default as a schema include for all entity kinds so
  # default aspects are resolved automatically. This replaces the old
  # *-to-default policies (host-to-default, user-to-default, home-to-default)
  # which created transitions to the "default" entity kind. Schema
  # includes are picked up by resolveEntity. The resolveEntityHandler
  # in pipeline.nix strips den.default from child entities resolved
  # during transitions to prevent cross-context duplicate resolution.
  config.den.schema = lib.mkIf (den ? default) (
    lib.genAttrs [ "host" "user" "home" ] (_: {
      includes = [ den.default ];
    })
  );
}
