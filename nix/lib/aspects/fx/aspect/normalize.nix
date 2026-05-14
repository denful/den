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
    # Synthetic provides: zero-arg functor returning an aspect-shaped value.
    # Resolve immediately so the pipeline sees name/includes directly.
    else if builtins.isFunction innerFn && innerArgs == { } && !(child ? __args) then
      let
        resolved = innerFn null;
      in
      if builtins.isAttrs resolved && resolved ? name && resolved ? includes then
        resolved
      else
        child
        // {
          __fn = innerFn;
          __args = { };
          includes = child.includes or [ ];
        }
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
    # Content wrapper from aspectContentType (has __contentValues but no name
    # yet).  Inject identity from __provider and extract parametric functions
    # into includes so the pipeline resolves them.  listOf doesn't call
    # providerType.merge per-element, so inner wrappers in includes lists
    # arrive here unprocessed.
    else if builtins.isAttrs child && child ? __contentValues && !(child ? name) then
      let
        prov = child.__provider or [ ];
        provName = if prov != [ ] then lib.last prov else null;
        fns = builtins.filter (
          d:
          lib.isFunction d.value
          && (
            let
              args = builtins.functionArgs d.value;
            in
            args != { } && !(args ? config) && !(args ? options)
          )
        ) child.__contentValues;
      in
      child
      // lib.optionalAttrs (provName != null) {
        name = provName;
        meta.provider = lib.init prov;
      }
      // lib.optionalAttrs (fns != [ ]) {
        includes = (child.includes or [ ]) ++ map (d: d.value) fns;
      }
    else
      child;
in
{
  inherit wrapChild isMeaningfulName;
}
