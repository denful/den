{ den, lib, ... }:
{
  options.den.default = lib.mkOption {
    description = "Default aspect";
    type = den.lib.aspects.types.aspectType;
  };

  # aspectType's meta-injecting merge only fires for options built through a
  # container that calls the element type's merge directly (den.aspects is
  # attrsOf aspectType). den.default is a bare top-level submodule option:
  # nixpkgs expands its nested-path definitions (den.default.includes = ...)
  # via the type's getSubOptions instead, which never calls the overridden
  # merge, so aspectMeta's mkDefault chain never lands and this reads null.
  # den.default is unambiguously a root — it is broadcast, never included by
  # anyone — so it states its own chain rather than relying on injection.
  config.den.default.meta.aspect-chain = lib.mkDefault [ ];

  # Inject den.default as a schema include for all entity kinds so
  # default aspects are resolved automatically. This replaces the old
  # *-to-default policies (host-to-default, user-to-default, home-to-default)
  # which created transitions to the "default" entity kind. Schema
  # includes are picked up by resolveEntity. Deduplication of
  # den.default modules across entity scopes is handled by key-based
  # dedup in wrapPerScope and extractSubtreeModules.
  config.den.schema = lib.mkIf (den ? default) (
    lib.genAttrs [ "host" "user" "home" ] (_: {
      includes = [ den.default ];
    })
  );
}
