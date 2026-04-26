# Compatibility shim: forwards den.ctx.* to den.entityIncludes/entityProvides
# with deprecation warnings.
# den.ctx was always flat (host, user, hm-host — never nested namespaces).
# Also handles den.ctx.*.into by forwarding to stage meta.into (transitional).
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

  # Forward den.ctx entries to stages (transitional — stages still read by resolveEntity).
  config.den.stages = lib.mkMerge (
    lib.mapAttrsToList (
      name: value:
      let
        intoFn = value.into or null;
        stageValue = builtins.removeAttrs value [ "into" ];
      in
      {
        ${name} =
          lib.warn "den.ctx.${name} is deprecated — use den.entityIncludes.${name}" stageValue
          // lib.optionalAttrs (intoFn != null) {
            meta.into = lib.warn "den.ctx.${name}.into is deprecated — use den.policies" intoFn;
          };
      }
    ) (builtins.removeAttrs config.den.ctx [ "_module" ])
  );
}
