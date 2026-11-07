# A policy applies to the entity it is registered on (#694 §11a R1): the
# registrant is the nearest own entity of the registering scope, by identity.
{ lib }:
let
  # { kind; record; } for the nearest scope on or above `scope` that has an
  # own entity, or null (a flake-level scope).
  registrantAt =
    state: scope:
    let
      kinds = (state.scopeEntityKind or (_: { })) null;
      ctxs = (state.scopeContexts or (_: { })) null;
      parents = (state.scopeParent or (_: { })) null;
      go =
        seen: s:
        if s == null || seen ? ${s} then
          null
        else
          let
            kind = kinds.${s} or null;
            record = if kind == null then null else (ctxs.${s} or { }).${kind} or null;
          in
          if record != null && record ? id_hash then
            { inherit kind record; }
          else
            go (seen // { ${s} = true; }) (parents.${s} or null);
    in
    go { } scope;

  # A registration shared with an ancestor scope (den.default, or one policy in
  # both a host's and its users' schema includes) is one instance where both
  # registrations assign the same relata: the ancestor, host side, wins (C2).
  # A policy that does not declare the descendant's kind (`{ host }`) keeps one
  # instance per registering scope (N1).
  outermostSharing =
    state: scope: key:
    let
      registry = (state.scopedAspectPolicies or (_: { })) null;
      parents = (state.scopeParent or (_: { })) null;
      go =
        seen: s: best:
        if s == null || seen ? ${s} then
          best
        else
          go (seen // { ${s} = true; }) (parents.${s} or null) (
            if (registry.${s} or { }) ? ${key} then s else best
          );
    in
    go { } scope null;

  registrantFor =
    state: scope: key: entry:
    let
      own = entry.registrant or (registrantAt state scope);
      outer = outermostSharing state scope key;
      outerRegistrant = if outer == null then null else registrantAt state outer;
      declared = lib.functionArgs entry.fn;
      bindsBoth =
        own != null
        && outerRegistrant != null
        && declared ? ${own.kind}
        && declared ? ${outerRegistrant.kind};
    in
    if outerRegistrant != null && bindsBoth then outerRegistrant else own;
in
{
  inherit registrantAt;

  # The policies a scope dispatches, each carrying its registrant.
  withRegistrants =
    state: scope: policies:
    lib.mapAttrs (key: entry: entry // { registrant = registrantFor state scope key entry; }) policies;
}
