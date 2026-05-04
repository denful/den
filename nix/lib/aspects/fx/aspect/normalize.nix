# Child normalization — coerce raw inputs into canonical aspect attrsets.
{
  lib,
  den,
}:
let
  inherit (den.lib.aspects) isSubmoduleFn isMeaningfulName isParametricWrapper;

  # Normalize a NixOS module function into an aspect attrset via type merge.
  normalizeModuleFn =
    child:
    den.lib.aspects.types.aspectType.merge
      [ (child.name or "<deferred>") ]
      [
        {
          file = "<deferred>";
          value = child;
        }
      ];

  wrapFunctorChild =
    child:
    let
      innerFn = child.__functor child;
      innerArgs = if builtins.isFunction innerFn then builtins.functionArgs innerFn else { };
    in
    if builtins.isFunction innerFn && isSubmoduleFn innerFn then
      normalizeModuleFn innerFn
    else
      child
      // {
        __fn =
          if child ? __args then
            child.__fn
          else if builtins.isFunction innerFn then
            innerFn
          else
            _: innerFn;
        __args =
          let
            explicit = child.__args or { };
          in
          if explicit != { } then explicit else innerArgs;
        includes = child.includes or [ ];
      };

  wrapBareFn =
    child:
    if isSubmoduleFn child then
      normalizeModuleFn child
    else
      {
        name = child.name or "<anon>";
        meta = child.meta or { };
        __fn = child;
        __args = lib.functionArgs child;
      };

  wrapChild =
    child:
    if lib.isFunction child then
      if builtins.isAttrs child && child ? name && child ? includes && builtins.isList child.includes then
        child
      else if builtins.isAttrs child then
        wrapFunctorChild child
      else
        wrapBareFn child
    else
      child;
in
{
  inherit wrapChild isMeaningfulName;
}
