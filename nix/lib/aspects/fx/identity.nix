{
  lib,
  den,
  ...
}:
let
  aspectPath =
    a:
    (a.meta.provider or [ ]) ++ [ (a.name or "<anon>") ] ++ lib.optional (a ? __ctxId) "{${a.__ctxId}}";

  pathKey = path: lib.concatStringsSep "/" path;

  # Composed: aspectPath → pathKey in one call.
  key = a: pathKey (aspectPath a);

  # Base identity without the {ctxId} instance suffix: provider chain + name.
  # The pretty, stable fully-qualified name (e.g. "roles/workstation").
  baseKey = a: pathKey ((a.meta.provider or [ ]) ++ [ (a.name or "<anon>") ]);

  # True when an identity string refers to an anonymous/unresolved node.
  isAnonIdentity =
    id:
    !(den.lib.aspects.isMeaningfulName id) || lib.hasPrefix "<root>/" id || lib.hasInfix "/<anon>:" id;

  # Strip the {ctxId} suffix from an identity, yielding the base identity.
  stripCtxSuffix = id: lib.head (lib.splitString "/{" id);

  # The entity bindings a ctx-qualified identity carries, as { kind = name; }.
  # handlers/bind.nix fans a descendant-arg aspect by appending `@<kind>=<name>`
  # per bound child and emits EVERY instance at the same scope, so the {ctxId}
  # suffix is the only record of which entity an instance belongs to. Identities
  # with no suffix (unfanned content) bind nothing and yield { }.
  ctxBindings =
    id:
    let
      parts = lib.splitString "/{" id;
    in
    if builtins.length parts < 2 then
      { }
    else
      builtins.listToAttrs (
        builtins.concatMap (
          pair:
          let
            kv = lib.splitString "=" pair;
          in
          lib.optional (builtins.length kv == 2) {
            name = builtins.head kv;
            value = lib.elemAt kv 1;
          }
        ) (builtins.tail (lib.splitString "@" (lib.removeSuffix "}" (lib.last parts))))
      );

  tombstone = resolved: extra: {
    name = "~${resolved.name or "<anon>"}";
    meta =
      (resolved.meta or { })
      // {
        excluded = true;
        originalName = resolved.name or "<anon>";
      }
      // extra;
    includes = [ ];
  };

  # The flat, scope-agnostic membership set: union of every per-scope bucket.
  # `pathSetByScope` is the single source of truth; consumers that don't care
  # about scope (structural hasAspect, capture) derive the flat view from it
  # instead of a separately-maintained flat field.
  flattenPathSetByScope = pbs: lib.foldl' (a: b: a // b) { } (builtins.attrValues pbs);

  collectPathsHandler = {
    "resolve-complete" =
      { param, state }:
      let
        isExcluded = param.meta.excluded or false;
        # The entity root (host/user/home) carries __entityKind. It is indexed
        # in pathSetByScope but excluded from resolvedNodes — an entity is not
        # one of its own aspects.
        isEntityRoot = param ? __entityKind;
        path = aspectPath param;
        nodeKey = pathKey path;
        # Also store base path (without ctxId) so hasAspect can match
        # without needing to know the specific context instance.
        nodeBaseKey = baseKey param;
      in
      {
        resume = param;
        state =
          state
          // lib.optionalAttrs (!isExcluded) {
            # The per-scope path set is the SINGLE membership record. Each node is
            # indexed under its currentScope by BOTH the ctx-qualified nodeKey and
            # the base key (without {ctxId}). The flat, scope-agnostic set some
            # consumers need is just the union of these buckets
            # (flattenPathSetByScope) — no separate flat field. Conditional guards
            # read a scope-restricted union (currentScope + ancestors, #613); the
            # entity-surface projected hasAspect reads one bucket by id_hash and
            # only the base key (the extra nodeKey entry is inert there).
            pathSetByScope =
              _:
              let
                prev = (state.pathSetByScope or (_: { })) null;
                scope = state.currentScope;
                scopeSet = prev.${scope} or { };
              in
              prev
              // {
                ${scope} =
                  scopeSet
                  // {
                    ${nodeKey} = true;
                  }
                  // lib.optionalAttrs (nodeBaseKey != nodeKey) {
                    ${nodeBaseKey} = true;
                  };
              };
          }
          // lib.optionalAttrs (!isExcluded && !isEntityRoot) {
            # Full resolved nodes keyed by unique (ctx-qualified) identity, for
            # host.aspects. Stored behind the state thunk so a deepSeq of state
            # never forces the node's class-content bodies (the lambda is WHNF);
            # only reading host.aspects materializes name/meta/identity.
            resolvedNodes =
              _:
              (state.resolvedNodes or (_: { })) null
              // {
                ${nodeKey} = param;
              };
          };
      };
  };

in
{
  inherit
    aspectPath
    pathKey
    key
    baseKey
    isAnonIdentity
    stripCtxSuffix
    ctxBindings
    tombstone
    flattenPathSetByScope
    collectPathsHandler
    ;
}
