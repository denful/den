# Child normalization — coerce raw inputs into canonical aspect attrsets.
{
  lib,
  den,
}:
let
  inherit (den.lib.aspects)
    isSubmoduleFn
    isMeaningfulName
    isParametricWrapper
    isParametricContent
    ;

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

  # A navigated nested aspect carries __aspectChain (its full path) but may have
  # no name yet. Derive name + meta.aspect-chain from it so the aspect resolves
  # to its OWN identity (e.g. apps/gaming/steam) regardless of inclusion path.
  # Without this it falls through nameless and children.nix renames it to
  # <parent>/<anon>:<idx>, so the same aspect included via two paths gets two
  # identities: it fails to dedup, and an exclude naming it never matches.
  withChainIdentity =
    child:
    let
      prov = child.__aspectChain or [ ];
    in
    if builtins.isAttrs child && !(child ? name) && prov != [ ] then
      child
      // {
        name = lib.last prov;
        meta.aspect-chain = lib.init prov;
      }
    else
      child;

  # A content wrapper (aspectContentType) is functor-bearing, so the function
  # branch below would claim it; but its functor only re-applies the merged
  # aspect and hides the parametric functions inside `__contentValues`. Those
  # must reach the pipeline as includes, resolved with the scope's entity
  # arguments, or their content is keyed by the wrapper alone and collapses
  # across hosts wherever several hosts merge into one evaluation.
  isContentWrapper =
    child:
    builtins.isAttrs child && (child ? __contentValues || child ? __aspectChain) && !(child ? name);

  wrapChild =
    child:
    if isContentWrapper child then
      let
        fns = builtins.filter isParametricContent (child.__contentValues or [ ]);
      in
      withChainIdentity child
      // lib.optionalAttrs (fns != [ ]) {
        includes = (child.includes or [ ]) ++ map (d: d.value) fns;
      }
    else if lib.isFunction child then
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
