{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx.handlers) constantHandler;
  inherit (den.lib.aspects.fx.aspect) structuralKeysSet;

  # Use the canonical structuralKeysSet from aspect.nix.  removeAttrs on
  # keys absent from stageNode is a no-op, so the superset is safe.
  structuralKeys = builtins.attrNames structuralKeysSet;

  resolveStage =
    name: ctx:
    let
      stageNode = den.stages.${name} or { };
      classAttrs = builtins.removeAttrs stageNode structuralKeys;
      scopeHandlers = constantHandler ctx;
    in
    classAttrs
    // {
      name = stageNode.name or name;
      meta = {
        handleWith = null;
        excludes = [ ];
        provider = [ ];
        into = stageNode.meta.into or null;
      };
      provides = stageNode.provides or { };
      includes = stageNode.includes or [ ];
      __ctx = ctx;
      __ctxStage = name;
      __scopeHandlers = scopeHandlers;
    };
in
resolveStage
