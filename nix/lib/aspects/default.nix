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

  # Structural keys the functor-root unwrap below re-derives itself, so the
  # general carry-forward must not copy them off the pre-normalization root:
  # name/meta/includes are defaulted explicitly; __fn/__args are built here
  # from the functor; __functor/__functionArgs are the function representation
  # this branch consumes into __fn/__args, and re-emitting them would leave the
  # root looking unnormalized to content-util's functor unwrap; _module is
  # module-system bookkeeping the aspect merge leaves behind (resolveAspectWith
  # strips it for the same reason), never pipeline state.
  functorRootOwnedKeys = lib.genAttrs [
    "name"
    "meta"
    "includes"
    "__fn"
    "__args"
    "__functor"
    "__functionArgs"
    "_module"
  ] (_: true);

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
      # Every other structural key on the root (excludes, provides, policies,
      # into, classes, __scopeHandlers, __walkStamped, …) survives the unwrap
      # unchanged — a whitelist here silently dropped each new marker.
      {
        __fn = resolved.__functor resolved;
        __args = functorArgs;
        name = resolved.name or "<function body>";
        meta = resolved.meta or { };
        includes = resolved.includes or [ ];
      }
      // lib.filterAttrs (
        k: _: fx.keyClassification.isStructuralKey k && !(functorRootOwnedKeys ? ${k})
      ) resolved
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

  # Like resolve but also surfaces the per-scope path set, from one fx.handle.
  fxResolveTreeWithPaths =
    class: resolved:
    let
      wrapped = normalizeRoot resolved;
      ctx = fx.aspect.ctxFromHandlers (resolved.__scopeHandlers or { });
    in
    fx.pipeline.fxResolveWithPaths {
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

  types = lib.mapAttrs (_: v: v { origin = [ ]; }) rawTypes;
in
{
  inherit
    types
    fx
    normalizeRoot
    policyTypes
    ;
  resolve = fxResolveTree;
  resolveWithPaths = fxResolveTreeWithPaths;
  resolveImports = fxResolveTreeImports;
  resolveWithState = fxResolveTreeFull;
  inherit (hasAspect)
    hasAspectIn
    collectPathSet
    mkEntityHasAspect
    mkProjectedHasAspect
    ;
  mkAspectsType = typeCfg: lib.mapAttrs (_: v: v typeCfg) rawTypes;
  # Predicates exported directly (not through types mapAttrs which applies { } to each value).
  inherit (rawTypes)
    isParametricWrapper
    isParametricContent
    isSubmoduleFn
    isMeaningfulName
    isSyntheticName
    ;
}
