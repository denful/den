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
          state =
            (scopedAppend state "scopedConstraintFilters" currentScope filterEntry)
            // {
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
            (
              state
              // {
                scopedConstraintRegistry =
                  _:
                  let
                    all = (state.scopedConstraintRegistry or (_: { })) null;
                    inherit (state) currentScope;
                    scopeData = all.${currentScope} or { };
                    existingScoped = scopeData.${param.identity} or [ ];
                  in
                  all
                  // {
                    ${currentScope} = scopeData // {
                      ${param.identity} = existingScoped ++ [ entry ];
                    };
                  };
              }
            )
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
        inherit (state) currentScope;
        # Use pre-merged flat views (O(1) instead of O(S) rebuild per call).
        registry = state.flatConstraintRegistry or { };
        filters = state.flatConstraintFilters or [ ];
        currentChain = ((state.scopedIncludesChain or (_: { })) null).${currentScope} or [ ];
        isAncestor = ownerChain: lib.take (builtins.length ownerChain) currentChain == ownerChain;
        inScope = entry: (entry.scope or "global") == "global" || isAncestor (entry.ownerChain or [ ]);
        mkDecision = action: extra: {
          resume = {
            inherit action;
          }
          // extra;
          inherit state;
        };
        entries = registry.${nodeIdentity} or [ ];
        prefixEntries =
          if registry == { } then
            [ ]
          else
            let
              parts = lib.splitString "/" nodeIdentity;
              prefixes = lib.genList (i: lib.concatStringsSep "/" (lib.take (i + 1) parts)) (
                builtins.length parts - 1
              );
              getEntries = p: registry.${p} or [ ];
            in
            if builtins.length parts > 1 then builtins.concatMap getEntries prefixes else [ ];
        allEntries = entries ++ prefixEntries;
        scopedEntries = builtins.filter inScope allEntries;
        firstEntry = if scopedEntries == [ ] then null else builtins.head scopedEntries;
      in
      if firstEntry != null then
        if firstEntry.type == "exclude" then
          mkDecision "exclude" { inherit (firstEntry) owner; }
        else if firstEntry.type == "substitute" then
          mkDecision "substitute" {
            replacement = firstEntry.getReplacement null;
            inherit (firstEntry) owner;
          }
        else
          mkDecision "keep" { }
      else
        let
          scopedFilters = builtins.filter inScope filters;
          failedFilter =
            if aspect != null then lib.findFirst (f: !(f.predicate aspect)) null scopedFilters else null;
        in
        if failedFilter != null then
          mkDecision "exclude" { inherit (failedFilter) owner; }
        else
          mkDecision "keep" { };
  };
in
{
  inherit constraintRegistryHandler;
}
