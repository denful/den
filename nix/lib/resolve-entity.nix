{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx.handlers) constantHandler;
  inherit (den.lib.aspects.fx.aspect) structuralKeysSet;

  structuralKeys = builtins.attrNames structuralKeysSet;

  # Entity resolution — replaces resolveStage.
  #
  # Root aspect: read from den.entityIncludes → placed in rootIncludes
  # (resolved before transitions) so deferred includes can drain during
  # context widening.
  # Cross-provides: read from den.entityProvides (used by transition handler).
  # Stage fallback: reads den.stages during migration.
  resolveEntity =
    name: ctx:
    let
      scopeHandlers = constantHandler ctx;

      # New entity data sources.
      entityIncludes = den.entityIncludes.${name} or [ ];
      entityProvides = den.entityProvides.${name} or { };

      # Stage fallback (transitional — will be removed with den.stages).
      stageNode = den.stages.${name} or { };
      stageIncludes = stageNode.includes or [ ];
      stageProvides = stageNode.provides or { };
      classAttrs = builtins.removeAttrs stageNode structuralKeys;
    in
    classAttrs
    // {
      inherit name;
      meta = {
        handleWith = null;
        excludes = [ ];
        provider = [ ];
        into = stageNode.meta.into or null;
      };
      # Root includes resolve before transitions.
      rootIncludes = entityIncludes;
      # Cross-provides: entity + stage merged (entity wins).
      provides = stageProvides // entityProvides;
      # Regular includes from stages (transitional).
      includes = stageIncludes;
      __ctxStage = name;
      __scopeHandlers = scopeHandlers;
    };
in
resolveEntity
