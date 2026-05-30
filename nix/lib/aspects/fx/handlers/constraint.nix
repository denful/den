# Effect handlers: register-constraint, check-constraint
# Manages the constraint registry (exclude, substitute, filter) and
# evaluates constraints against node identities during tree walk.
{
  lib,
  den,
  ...
}:
let
  inherit (import ./state-util.nix) scopedAppend;

  lookupEntries =
    registry: nodeIdentity:
    let
      exact = registry.${nodeIdentity} or [ ];
      parts = lib.splitString "/" nodeIdentity;
      prefixes = lib.genList (i: lib.concatStringsSep "/" (lib.take (i + 1) parts)) (
        builtins.length parts - 1
      );
    in
    if registry == { } then
      exact
    else if builtins.length parts > 1 then
      exact ++ builtins.concatMap (p: registry.${p} or [ ]) prefixes
    else
      exact;

  filterByScope =
    currentChain: entries:
    let
      isAncestor = ownerChain: lib.take (builtins.length ownerChain) currentChain == ownerChain;
      inScope = entry: (entry.scope or "global") == "global" || isAncestor (entry.ownerChain or [ ]);
    in
    builtins.filter inScope entries;

  entryToResume =
    entry:
    if entry.type == "exclude" then
      {
        action = "exclude";
        inherit (entry) owner;
      }
    else if entry.type == "substitute" then
      {
        action = "substitute";
        replacement = entry.getReplacement null;
        inherit (entry) owner;
      }
    else
      { action = "keep"; };

  constraintRegistryHandler = {
    "register-constraint" =
      { param, state }:
      let
        inherit (state) currentScope;
        ownerChain = ((state.scopedIncludesChain or (_: { })) null).${currentScope} or [ ];
        scope = param.scope or "subtree";
      in
      if param.type == "filter" then
        let
          filterEntry = {
            inherit (param) predicate;
            owner = param.owner or "<anon>";
            inherit scope ownerChain;
          };
        in
        {
          resume = null;
          state = (scopedAppend state "scopedConstraintFilters" currentScope filterEntry) // {
            flatConstraintFilters = (state.flatConstraintFilters or [ ]) ++ [ filterEntry ];
          };
        }
      else
        let
          entry = {
            inherit (param) type;
            getReplacement = param.getReplacement or (_: null);
            owner = param.owner or "<anon>";
            inherit scope ownerChain;
          };
          flatReg = state.flatConstraintRegistry or { };
          existing = flatReg.${param.identity} or [ ];
        in
        {
          resume = null;
          state =
            let
              all = (state.scopedConstraintRegistry or (_: { })) null;
              inherit (state) currentScope;
              scopeData = all.${currentScope} or { };
              updatedRegistry = all // {
                ${currentScope} = scopeData // {
                  ${param.identity} = (scopeData.${param.identity} or [ ]) ++ [ entry ];
                };
              };
            in
            (state // { scopedConstraintRegistry = _: updatedRegistry; })
            // {
              flatConstraintRegistry = flatReg // {
                ${param.identity} = existing ++ [ entry ];
              };
            };
        };

    "check-constraint" =
      { param, state }:
      let
        nodeIdentity = if builtins.isAttrs param then param.identity else param;
        aspect = if builtins.isAttrs param then param.aspect or null else null;
        currentChain = ((state.scopedIncludesChain or (_: { })) null).${state.currentScope} or [ ];
        allEntries = lookupEntries (state.flatConstraintRegistry or { }) nodeIdentity;
        scopedEntries = filterByScope currentChain allEntries;
        firstEntry = if scopedEntries == [ ] then null else builtins.head scopedEntries;
      in
      if firstEntry != null then
        {
          resume = entryToResume firstEntry;
          inherit state;
        }
      else
        let
          scopedFilters = filterByScope currentChain (state.flatConstraintFilters or [ ]);
          failedFilter =
            if aspect != null then lib.findFirst (f: !(f.predicate aspect)) null scopedFilters else null;
        in
        if failedFilter != null then
          {
            resume = {
              action = "exclude";
              inherit (failedFilter) owner;
            };
            inherit state;
          }
        else
          {
            resume = {
              action = "keep";
            };
            inherit state;
          };
  };
in
{
  inherit constraintRegistryHandler lookupEntries;
}
