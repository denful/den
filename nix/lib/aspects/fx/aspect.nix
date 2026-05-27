{
  lib,
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;
  inherit (den.lib.aspects.fx.keyClassification) structuralKeysSet;
  inherit (import ./class-module.nix { inherit lib den; }) wrapClassModule;

  ctxFromHandlers =
    handlers:
    lib.mapAttrs (
      _: handler:
      (handler {
        param = null;
        state = { };
      }).resume
    ) handlers;

  inherit (import ./aspect { inherit lib den; } { inherit ctxFromHandlers; })
    emitIncludes
    emitAspectPolicies
    ;

  enterScope =
    handlers: computation:
    fx.effects.scope.provide handlers (
      fx.bind (fx.send "scope-widened" { ctx = ctxFromHandlers handlers; }) (_: computation)
    );

  # --- Parametric resolution ---

  # Build the base attrset for a parametric resolution result.
  mkParametricBase =
    aspect: resolved:
    {
      inherit (aspect) name;
      meta =
        (aspect.meta or { })
        // (if builtins.isAttrs resolved then resolved.meta or { } else { })
        // {
          isParametric = true;
          fnArgNames = builtins.attrNames (aspect.__args or { });
        };
    }
    // lib.optionalAttrs (aspect ? into) { inherit (aspect) into; }
    // lib.optionalAttrs (aspect ? provides) { inherit (aspect) provides; };

  # Merge the resolved value into the parametric base.
  mkParametricNext =
    aspect: base: resolved:
    if lib.isFunction resolved && !builtins.isAttrs resolved then
      if den.lib.aspects.isSubmoduleFn resolved then
        let
          merged = den.lib.aspects.types.aspectType.merge (aspect.meta.loc or [ (aspect.name or "<anon>") ]) [
            {
              file = aspect.meta.file or "<parametric>";
              value = resolved;
            }
          ];
        in
        base // builtins.removeAttrs merged [ "meta" ]
      else
        base
        // {
          __fn = resolved;
          __args = lib.functionArgs resolved;
        }
    else
      base // builtins.removeAttrs resolved [ "meta" ];

  # Tag a parametric result with scope propagation and depth tracking.
  tagParametricResult =
    aspect: next:
    let
      parentScopeHandlers = aspect.__scopeHandlers or { };
      resolvedScopeHandlers = if builtins.isAttrs next then next.__scopeHandlers or { } else { };
      mergedScopeHandlers = parentScopeHandlers // resolvedScopeHandlers;
    in
    next
    // lib.optionalAttrs (mergedScopeHandlers != { }) { __scopeHandlers = mergedScopeHandlers; }
    // lib.optionalAttrs (aspect ? __ctxId) { inherit (aspect) __ctxId; }
    // {
      __parametricResolvedArgs =
        (aspect.__parametricResolvedArgs or [ ]) ++ builtins.attrNames (aspect.__args or { });
    };

  maxParametricDepth = 10;

  # Prepare the fn for parametric resolution (scope injection + exactMatch handling).
  prepareParametricFn =
    aspect:
    let
      scopeHandlers = aspect.__scopeHandlers or null;
      scopeFn = if scopeHandlers != null then fx.effects.scope.provide scopeHandlers else null;
      rawFn = aspect.__fn;
      fn =
        if (aspect.meta.exactMatch or false) && scopeHandlers != null then
          args: rawFn (args // { __scopeKeys = builtins.attrNames scopeHandlers; })
        else
          rawFn;
      # nix-effects bind.fn uses lib.functionArgs internally but __args
      # overrides win via //. Values of true (= has default / optional) must
      # use the bindAttrs sentinel so the handler probe kicks in; passing
      # literal true would send it as a param and throw when unhandled.
      optionalArg = {
        __bindAttrsOptional = true;
      };
      args = lib.mapAttrs (_: v: if v == true then optionalArg else v) (aspect.__args or { });
      bound = fx.bind.fn args fn;
    in
    if scopeFn != null then scopeFn bound else bound;

in
{
  inherit
    emitIncludes
    emitAspectPolicies
    structuralKeysSet
    wrapClassModule
    ctxFromHandlers
    enterScope
    mkParametricBase
    mkParametricNext
    tagParametricResult
    prepareParametricFn
    maxParametricDepth
    ;
}
