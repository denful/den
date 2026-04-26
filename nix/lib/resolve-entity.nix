{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx.handlers) constantHandler;
  inherit (den.lib.aspects.fx.aspect) structuralKeysSet;

  structuralKeys = builtins.attrNames structuralKeysSet;

  resolveEntity =
    name: ctx:
    let
      scopeHandlers = constantHandler ctx;

      # Entity includes from the new registry (replaces den.stages.*.includes).
      entityIncludes = den.entityIncludes.${name} or [ ];

      # Stage data (transitional — read until all modules migrate).
      stageNode = den.stages.${name} or { };
      stageIncludes = stageNode.includes or [ ];
      classAttrs = builtins.removeAttrs stageNode structuralKeys;

      # Self-provide: derive from entity context when available,
      # fall back to stage provides during migration.
      entity = ctx.${name} or null;
      hasEntityAspect = entity != null && entity ? aspect;
      stageProvides = stageNode.provides or { };
      # Prefer stage provides when available (they use named function args
      # that the pipeline's self-provide resolution depends on).
      # Entity-derived self-provide is a fallback for when stages are gone.
      provides =
        if stageProvides ? ${name} then
          stageProvides
        else if hasEntityAspect then
          stageProvides // { ${name} = _: entity.aspect; }
        else
          stageProvides;
    in
    classAttrs
    // {
      inherit name provides;
      meta = {
        handleWith = null;
        excludes = [ ];
        provider = [ ];
        into = stageNode.meta.into or null;
      };
      includes = entityIncludes ++ stageIncludes;
      __ctxStage = name;
      __scopeHandlers = scopeHandlers;
    };
in
resolveEntity
