# Entity-facing wiring lives in modules/context/has-aspect.nix.
{ lib, den, ... }:
let
  inherit (den.lib.aspects.fx) identity;
  inherit (identity) aspectPath pathKey;

  refKey =
    ref:
    if (ref ? name) && (ref ? meta) then
      pathKey (aspectPath ref)
    else if ref ? __provider then
      # Nested aspect from freeform traversal — content merger sets __provider
      # but not name/meta. Derive path key from the provider chain.
      pathKey ref.__provider
    else
      throw "hasAspect: ref must have `name`+`meta` or `__provider` (got ${builtins.typeOf ref}).";

  # Resolve tree via fx pipeline and extract pathSet from state.
  # Inlines the same root normalization as fxResolveTree (default.nix)
  # to handle raw lambdas and functor attrsets.
  collectPathSet =
    { tree, class }:
    let
      normalized = den.lib.aspects.normalizeRoot tree;
      result = den.lib.aspects.fx.pipeline.fxFullResolve {
        inherit class;
        ctx = den.lib.aspects.fx.aspect.ctxFromHandlers (
          normalized.__scopeHandlers or tree.__scopeHandlers or { }
        );
        self = normalized;
      };
    in
    (result.state.pathSet or (_: { })) null;

  hasAspectIn =
    {
      tree,
      class,
      ref,
    }:
    (collectPathSet { inherit tree class; }) ? ${refKey ref};

  # Projected hasAspect: pure lookup over an already-computed per-scope path
  # set (byproduct of the owning entity's production run). No pipeline.
  # `pathSetByScope`/`scopeId` are read lazily — forced only when the result
  # boolean is scrutinised (e.g. at a class-module `mkIf`, post-run).
  mkProjectedHasAspect =
    { pathSetByScope, scopeId }:
    let
      check = ref: (pathSetByScope.${scopeId} or { }) ? ${refKey ref};
    in
    {
      __functor = _: check;
      forClass = _class: check; # structural set is class-invariant (matches mkEntityHasAspect)
      forAnyClass = check;
    };

  mkEntityHasAspect =
    {
      tree,
      primaryClass,
      classes,
    }:
    let
      setFor = builtins.listToAttrs (
        map (c: {
          name = c;
          value = collectPathSet {
            inherit tree;
            class = c;
          };
        }) (lib.unique ([ primaryClass ] ++ classes))
      );
      check = class: ref: (setFor.${class} or { }) ? ${refKey ref};
      bareFn = check primaryClass;
    in
    {
      __functor = _: bareFn;
      forClass = check;
      forAnyClass = ref: lib.any (c: check c ref) classes;
    };

in
{
  inherit
    hasAspectIn
    collectPathSet
    mkEntityHasAspect
    mkProjectedHasAspect
    ;
}
