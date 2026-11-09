# A policy applies to the entity it is registered on (#694 §11a R1): the
# registrant is the nearest own entity of the registering scope, by identity.
{ lib }:
let
  inherit (import ./entity-identity.nix { inherit lib; }) sameEntity entityKey;
  # Two registrants (or a registrant and a scope's own entity) are one entity.
  isRegistrant = a: b: a.kind == b.kind && sameEntity a.kind a.record b.record;

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
          if builtins.isAttrs record then
            { inherit kind record; }
          else
            go (seen // { ${s} = true; }) (parents.${s} or null);
    in
    go { } scope;

  # A policy registered inside a registrant's delivered include (dispatch.nix
  # sets the token `<registrant key>/<policy>` on it) inherits
  # that registrant, an ancestor of where it registers (#694 §11a C4).
  inheritedAt =
    state: scope:
    let
      # A registrant token starts with an entity key (its id_hash, or
      # `<kind>:<name>` without one) and `/`; a mutual-provider token names an
      # aspect instead, so it matches no registrant on the path. Read from
      # den's provenance stack, never from aspect names.
      tokens = (import ../handlers/provenance.nix { inherit lib; }).stackTokensOf state scope;
      parents = (state.scopeParent or (_: { })) null;
      # The registrants on the path, nearest first.
      path =
        seen: s:
        if s == null || seen ? ${s} then
          [ ]
        else
          let
            r = registrantAt state s;
          in
          lib.optional (r != null) r ++ path (seen // { ${s} = true; }) (parents.${s} or null);
      onPath = path { } scope;
      named = t: builtins.filter (r: lib.hasPrefix "${entityKey r.kind r.record}/" t) onPath;
      # The innermost registrant token wins, as its nearest registrant.
      matched = builtins.filter (rs: rs != [ ]) (map named tokens);
    in
    if matched == [ ] then null else builtins.head (lib.last matched);

  # Where a registrant's host-class part lands (#694 §11a R3 (a)): the
  # registrant itself when it has a class, else the nearest entity with a class
  # on the scope path from the registrant down to the firing scope.
  classTargetFor =
    state: scope: registrant:
    let
      parents = (state.scopeParent or (_: { })) null;
      # Own entities from the firing scope up to (not including) the
      # registrant's, nearest-to-firing first.
      go =
        seen: s:
        if s == null || seen ? ${s} then
          [ ]
        else
          let
            r = registrantAt state s;
          in
          if r != null && isRegistrant r registrant then
            [ ]
          else
            lib.optional (r != null) r ++ go (seen // { ${s} = true; }) (parents.${s} or null);
      classed = builtins.filter (r: r.record ? class) (lib.unique (go { } scope));
    in
    if registrant.record ? class then
      registrant
    else if classed == [ ] then
      null
    else
      lib.last classed;

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
      # The other registration wins only from above: a scope that binds the
      # recorded registrant is that registrant or below it (an inherited
      # registrant, C4, registers below itself).
      outerCtx = ((state.scopeContexts or (_: { })) null).${outer} or { };
      outerIsBelowOwn =
        own != null
        && builtins.isAttrs (outerCtx.${own.kind} or null)
        && sameEntity own.kind outerCtx.${own.kind} own.record;
    in
    if outerRegistrant != null && bindsBoth && !outerIsBelowOwn then outerRegistrant else own;
in
{
  inherit registrantAt entityKey;

  # The registrant recorded when a policy registers at `scope`.
  registrantOnRegister =
    state: scope:
    let
      inherited = inheritedAt state scope;
    in
    if inherited != null then inherited else registrantAt state scope;

  # The policies a scope dispatches, each carrying its registrant.
  withRegistrants =
    state: scope: policies:
    lib.mapAttrs (
      key: entry:
      let
        registrant = registrantFor state scope key entry;
      in
      entry
      // {
        registrant =
          if registrant == null then
            null
          else
            registrant // { classTarget = classTargetFor state scope registrant; };
      }
    ) policies;
}
