{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx.handlers) constantHandler;
  inherit (den.lib.aspects.fx.aspect) structuralKeysSet;

  structuralKeys = builtins.attrNames structuralKeysSet;

  # Thinner entity resolution — replaces resolveStage.
  #
  # During migration, reads provides/includes/classAttrs from den.stages
  # (same data as resolveStage). Will be simplified once stages are removed.
  resolveEntity =
    name: ctx:
    let
      scopeHandlers = constantHandler ctx;
      stageNode = den.stages.${name} or { };
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
      provides = stageNode.provides or { };
      includes = stageNode.includes or [ ];
      __ctxStage = name;
      __scopeHandlers = scopeHandlers;
    };
in
resolveEntity
