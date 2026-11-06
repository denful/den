# Shared subtree walk + key-dedup for the delivery half.
#
# One walk implementation backs every "scope + descendants" collection in the
# pipeline (default fold, route subtree collect, per-host re-walk, spawn final
# extraction) and the edge-trace oracle, so production and oracle can never
# diverge. The `isolated` argument is REQUIRED at every call site: there is no
# default. Two live callers need the isolation-BLIND variant (`isolated = {}`)
# and they are NOT the same call site: the per-host re-walk's
# sub-phase collect, and spawn-node's final extraction. Defaulting `isolated`
# would silently collapse this deliberate blind/aware split.
{ lib, ... }:
{
  # Scope IDs in `root`'s subtree. `root` is ALWAYS included: isolation gates
  # crossing INTO a descendant, not collecting AT the root. `isolated` is a
  # `{ <sid> = bool; }` map; `isolated = {}` gives the isolation-blind variant.
  subtreeScopes =
    {
      scopeParent,
      isolated,
      root,
      allScopeIds,
    }:
    let
      isIn =
        sid:
        sid == root
        || (
          !(isolated.${sid} or false)
          && (
            let
              parent = scopeParent.${sid} or null;
            in
            parent != null && parent != sid && isIn parent
          )
        );
    in
    builtins.filter isIn allScopeIds;

  # sid → id_hash of the scope's own entity: the record push-scope linked in
  # scopeByEntity (keyed "${parent}\n${id_hash}"), plus the resolved root's own
  # record. Scopes with no own entity are absent.
  ownEntityMap =
    {
      scopeByEntity,
      rootScopeId,
      rootIdHash,
    }:
    lib.mapAttrs' (k: sid: lib.nameValuePair sid (lib.last (lib.splitString "\n" k))) scopeByEntity
    // lib.optionalAttrs (rootIdHash != null) { ${rootScopeId} = rootIdHash; };

  # First-occurrence-wins dedup of `list` by the key `getKey` extracts from each
  # element. Elements whose key is null are always kept (never deduped).
  dedupByKey =
    getKey: list:
    let
      go =
        seen: items:
        if items == [ ] then
          [ ]
        else
          let
            x = builtins.head items;
            rest = builtins.tail items;
            k = getKey x;
          in
          if k != null && seen ? ${k} then
            go seen rest
          else
            [ x ] ++ go (if k != null then seen // { ${k} = true; } else seen) rest;
    in
    go { } list;
}
