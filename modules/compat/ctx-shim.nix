# DEPRECATED: scheduled for removal after first stable release post-fx-pipeline merge.
# Migration: use den.aspects.{name} instead of den.ctx.{name}.
# Compatibility shim: forwards den.ctx.* to den.aspects
# with deprecation warnings.
# den.ctx was always flat (host, user, hm-host — never nested namespaces).
# Remove after downstream users have migrated.
{
  den,
  lib,
  config,
  ...
}:
let
  ctxSubmodule = lib.types.submodule {
    imports = den.lib.aspects.types.aspectType.getSubModules;
    options.into = lib.mkOption {
      description = "DEPRECATED: use den.policies instead.";
      type = lib.types.nullOr lib.types.raw;
      default = null;
    };
  };
in
{
  options.den.ctx = lib.mkOption {
    description = "DEPRECATED: use den.aspects instead.";
    default = { };
    type = lib.types.lazyAttrsOf ctxSubmodule;
  };

  # Forward den.ctx entries as schema includes so they participate in entity resolution.
  config.den.schema = lib.mkMerge (
    lib.mapAttrsToList (
      name: value:
      let
        stageValue = builtins.removeAttrs value [
          "into"
          "_module"
        ];
      in
      {
        ${name}.includes = [
          (lib.warn "den.ctx.${name} is deprecated — use den.schema.${name}.includes" stageValue)
        ];
      }
    ) (builtins.removeAttrs config.den.ctx [ "_module" ])
  );
}
