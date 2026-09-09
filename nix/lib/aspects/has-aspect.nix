# Entity-facing wiring lives in modules/context/has-aspect.nix.
{ lib, den, ... }:
let
  inherit (den.lib.aspects.fx) identity;
  inherit (identity) aspectPath pathKey;

  refKey =
    ref:
    if (ref ? name) && (ref ? meta) then
      pathKey (aspectPath ref)
    else if ref ? __aspectChain then
      # Nested aspect from freeform traversal — content merger sets __aspectChain
      # but not name/meta. Derive path key from the provider chain.
      pathKey ref.__aspectChain
    else
      throw "hasAspect: ref must have `name`+`meta` or `__aspectChain` (got ${builtins.typeOf ref}).";

  # Resolve tree via fx pipeline, returning the full result state. One run
  # yields both the pathSet (membership, for hasAspect) and resolvedNodes
  # (for .aspects), so callers share a single resolution per class.
  # Inlines the same root normalization as fxResolveTree (default.nix)
  # to handle raw lambdas and functor attrsets.
  resolveClassState =
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
    result.state;

  collectPathSet =
    { tree, class }:
    identity.flattenPathSetByScope (
      ((resolveClassState { inherit tree class; }).pathSetByScope or (_: { })) null
    );

  hasAspectIn =
    {
      tree,
      class,
      ref,
    }:
    (collectPathSet { inherit tree class; }) ? ${refKey ref};

  # Projected hasAspect: pure lookup over an already-computed per-scope path
  # set (byproduct of the owning entity's production run), keyed by entity
  # identity (`id_hash`). No pipeline. `pathSetByScope`/`key` are read lazily —
  # forced only when the result boolean is scrutinised (e.g. at a class-module
  # `mkIf`, post-run).
  mkProjectedHasAspect =
    { pathSetByScope, key }:
    let
      check = ref: key != null && (pathSetByScope.${key} or { }) ? ${refKey ref};
    in
    {
      __functor = _: check;
      forClass = _class: check; # structural set is class-invariant (matches mkEntityHasAspect)
      forAnyClass = check;
    };

  # Augment a resolved node with its identity accessors for .aspects callers.
  # Shallow: every node already appears as its own flat entry, so children
  # reached via `.includes` are also present (augmented) at top level.
  augment =
    node:
    let
      baseId = identity.baseKey node;
    in
    node
    // {
      # Base FQN, ctx-stripped — pretty + stable (e.g. "roles/workstation").
      identity = baseId;
      # Full unique key incl {ctxId} — distinguishes anonymous instances.
      identityKey = identity.key node;
      # Named only if neither the node's own name nor any provider-chain segment
      # is an anonymous/synthetic sentinel. isMeaningfulName catches an exact
      # "<anon>"/"<function body>"/"[definition …]" name; the infix guards catch
      # nested anonymous instances like "roles/dev/<anon>:3" (whose name
      # "<anon>:3" slips past isMeaningfulName), so consumers can filter on it.
      isNamed =
        den.lib.aspects.isMeaningfulName (node.name or "<anon>")
        && !(lib.hasInfix "<anon>" baseId)
        && !(lib.hasInfix "<function body>" baseId);
    };

  mkEntityHasAspect =
    {
      tree,
      primaryClass,
      classes,
    }:
    let
      # One resolution per unique class, shared between membership (pathSet)
      # and the node list (resolvedNodes).
      stateFor = builtins.listToAttrs (
        map (c: {
          name = c;
          value = resolveClassState {
            inherit tree;
            class = c;
          };
        }) (lib.unique ([ primaryClass ] ++ classes))
      );
      pathSetFor =
        c: identity.flattenPathSetByScope (((stateFor.${c} or { }).pathSetByScope or (_: { })) null);
      nodesFor =
        c: map augment (lib.attrValues (((stateFor.${c} or { }).resolvedNodes or (_: { })) null));
      check = class: ref: (pathSetFor class) ? ${refKey ref};
    in
    {
      __functor = _: check primaryClass;
      forClass = check;
      forAnyClass = ref: lib.any (c: check c ref) classes;

      # Flat list of all resolved aspect nodes (every depth) for the primary
      # class, each augmented with .identity / .identityKey / .isNamed.
      aspects = nodesFor primaryClass;
      aspectsForClass = nodesFor;
      # Union across classes, deduped by full identity key.
      allAspects = lib.attrValues (
        builtins.listToAttrs (map (n: lib.nameValuePair n.identityKey n) (lib.concatMap nodesFor classes))
      );
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
