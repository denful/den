{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx.handlers) constantHandler;

  # Thinner entity resolution — replaces resolveStage.
  # Entity includes come from den.stages.${name}.includes for now;
  # Task 3 will switch to entity schema includes.
  resolveEntity =
    name: ctx:
    let
      scopeHandlers = constantHandler ctx;
      stageIncludes = (den.stages.${name} or { }).includes or [ ];
    in
    {
      inherit name;
      meta = {
        handleWith = null;
        excludes = [ ];
        provider = [ ];
        into = null;
      };
      provides = { };
      includes = stageIncludes;
      __ctxStage = name;
      __scopeHandlers = scopeHandlers;
    };
in
resolveEntity
