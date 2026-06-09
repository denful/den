# nix/lib/entities/_types.nix
#
# Shared helpers for entity type definitions.
# Extracted from nix/lib/types.nix — no new functionality.
{
  lib,
  ...
}:
let
  strOpt =
    description: default:
    lib.mkOption {
      type = lib.types.str;
      inherit description default;
    };

  # Shared aspect lookup with warning for missing aspects.
  lookupAspect =
    den: config:
    if den.aspects ? ${config.name} then
      den.aspects.${config.name}
    else
      lib.warn "den.aspects.${config.name} not defined — entity gets empty aspect" { };

  # Single shared production run: imports + per-scope path set from ONE fx.handle.
  # Declared as an option so the module fixpoint memoizes it — every consumer
  # (mainModule, __pathSetByScope) reads the same value, guaranteeing one resolve.
  resolveResultOption =
    den: config:
    lib.mkOption {
      internal = true;
      visible = false;
      readOnly = true;
      type = lib.types.raw;
      defaultText = "den.lib.aspects.resolveWithPaths config.class config.resolved";
      default = den.lib.aspects.resolveWithPaths config.class config.resolved;
    };

  # mainModule now derives imports from the shared result (no second run).
  mainModuleOption =
    _den: config:
    lib.mkOption {
      internal = true;
      visible = false;
      readOnly = true;
      type = lib.types.deferredModule;
      defaultText = "{ inherit (config.__resolveResult) imports; }";
      default = { inherit (config.__resolveResult) imports; };
    };

  # Per-scope path set, surfaced for the projected (in-context) hasAspect.
  pathSetByScopeOption =
    _den: config:
    lib.mkOption {
      internal = true;
      visible = false;
      readOnly = true;
      type = lib.types.raw;
      defaultText = "config.__resolveResult.pathSetByScope";
      default = config.__resolveResult.pathSetByScope;
    };
in
{
  inherit
    strOpt
    lookupAspect
    mainModuleOption
    resolveResultOption
    pathSetByScopeOption
    ;
}
