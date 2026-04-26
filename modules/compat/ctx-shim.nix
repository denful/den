# Compatibility shim: forwards den.ctx.* to den.entityIncludes
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
    description = "DEPRECATED: use den.entityIncludes instead.";
    default = { };
    type = lib.types.lazyAttrsOf ctxSubmodule;
  };

  # Forward den.ctx entries as entityIncludes.
  config.den.entityIncludes = lib.mkMerge (
    lib.mapAttrsToList (
      name: value:
      let
        stageValue = builtins.removeAttrs value [
          "into"
          "_module"
        ];
      in
      {
        ${name} = [
          (lib.warn "den.ctx.${name} is deprecated — use den.entityIncludes.${name}" stageValue)
        ];
      }
    ) (builtins.removeAttrs config.den.ctx [ "_module" ])
  );
}
