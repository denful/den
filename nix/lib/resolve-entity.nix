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
      stageProvides = stageNode.provides or { };
      provides = stageProvides;
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
