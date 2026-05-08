{
  lib,
  den,
  ...
}:
let
  rawTypes = import ./types.nix { inherit den lib; };
  policyTypes = import ./policy-type.nix { inherit lib; };
  hasAspect = import ./has-aspect.nix { inherit den lib; };
  fx = import ./fx { inherit den lib; };

  normalizeRoot =
    resolved:
    let
      isBareFn = lib.isFunction resolved && !builtins.isAttrs resolved;
      isFunctor =
        !isBareFn
        && builtins.isAttrs resolved
        && resolved ? __functor
        && builtins.isFunction (resolved.__functor resolved);
      functorArgs = if isFunctor then builtins.functionArgs (resolved.__functor resolved) else { };
      needsWrap = isFunctor && functorArgs != { };
      bareFnArgs = if isBareFn then lib.functionArgs resolved else { };
      isModuleFn = isBareFn && rawTypes.isSubmoduleFn resolved;
    in
    if isModuleFn then
      den.lib.aspects.types.aspectType.merge
        [ "<bare-module>" ]
        [
          {
            file = "<bare-module>";
            value = resolved;
          }
        ]
    else if isBareFn then
      {
        __fn = resolved;
        __args = bareFnArgs;
        name = "<bare-fn>";
        meta = { };
      }
    else if needsWrap then
      {
        __fn = resolved.__functor resolved;
        __args = functorArgs;
        name = resolved.name or "<function body>";
        meta = resolved.meta or { };
        includes = resolved.includes or [ ];
      }
      // lib.optionalAttrs (resolved ? __scopeHandlers) { inherit (resolved) __scopeHandlers; }
    else
      resolved;

  fxResolveTree =
    class: resolved:
    let
      wrapped = normalizeRoot resolved;
      ctx = fx.aspect.ctxFromHandlers (resolved.__scopeHandlers or { });
    in
    fx.pipeline.fxResolve {
      inherit class ctx;
      self = wrapped;
    };

  # Like resolve but skips entity instantiation.
  # Use for nested resolution (e.g., extracting homeManager modules from a host tree).
  fxResolveTreeImports =
    class: resolved:
    let
      wrapped = normalizeRoot resolved;
      ctx = fx.aspect.ctxFromHandlers (resolved.__scopeHandlers or { });
    in
    fx.pipeline.fxResolveImports {
      inherit class ctx;
      self = wrapped;
    };

  # Like resolve but returns full pipeline result including state.
  fxResolveTreeFull =
    class: resolved:
    let
      wrapped = normalizeRoot resolved;
      ctx = fx.aspect.ctxFromHandlers (resolved.__scopeHandlers or { });
    in
    fx.pipeline.fxFullResolve {
      inherit class ctx;
      self = wrapped;
    };

  types = lib.mapAttrs (_: v: v { }) rawTypes;
in
{
  inherit
    types
    fx
    normalizeRoot
    policyTypes
    ;
  resolve = fxResolveTree;
  resolveImports = fxResolveTreeImports;
  resolveWithState = fxResolveTreeFull;
  inherit (hasAspect) hasAspectIn collectPathSet mkEntityHasAspect;
  mkAspectsType = typeCfg: lib.mapAttrs (_: v: v typeCfg) rawTypes;
  # Predicates exported directly (not through types mapAttrs which applies { } to each value).
  inherit (rawTypes)
    isParametricWrapper
    isSubmoduleFn
    isMeaningfulName
    ;
}
