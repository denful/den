{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx.handlers) constantHandler;

  # Entity resolution — the sole resolution path.
  #
  # Root aspect: read from den.entityIncludes → placed in rootIncludes
  # (resolved before transitions) so deferred includes can drain during
  # context widening.
  # Cross-provides: read from den.entityProvides (used by transition handler).
  resolveEntity =
    name: ctx:
    let
      scopeHandlers = constantHandler ctx;
      entityIncludes = den.entityIncludes.${name} or [ ];
      entityProvides = den.entityProvides.${name} or { };
    in
    {
      inherit name;
      meta = {
        handleWith = null;
        excludes = [ ];
        provider = [ ];
        into = null;
      };
      rootIncludes = entityIncludes;
      provides = entityProvides;
      includes = [ ];
      __ctxStage = name;
      __scopeHandlers = scopeHandlers;
    };
in
resolveEntity
