{
  lib,
  den,
  ...
}:
let
  inherit (import ./state-util.nix) scopedAppend scopedMerge;

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

  chainHandler = {
    "chain-push" =
      { param, state }:
      {
        resume = null;
        state = state // {
          scopedIncludesChain =
            _:
            let
              all = (state.scopedIncludesChain or (_: { })) null;
              inherit (state) currentScope;
              scopeChain = all.${currentScope} or [ ];
            in
            all
            // {
              ${currentScope} = scopeChain ++ [ param.identity ];
            };
        };
      };
    "chain-pop" =
      { param, state }:
      {
        resume = null;
        state = state // {
          scopedIncludesChain =
            _:
            let
              all = (state.scopedIncludesChain or (_: { })) null;
              inherit (state) currentScope;
              scopeChain = all.${currentScope} or [ ];
            in
            all
            // {
              ${currentScope} =
                if scopeChain == [ ] then
                  throw "fx: chain-pop on empty scopedIncludesChain"
                else
                  lib.init scopeChain;
            };
        };
      };
  };

  classCollectorHandler = {
    "emit-class" =
      { param, state }:
      let
        nodeIdentity = param.identity or "<anon>";
        isRawEntry = param.__rawEntry or false;
        # Raw entries always use full identity (conservative dedup).
        # Post-pipeline wrapping may relax identity if module turns out
        # not context-dependent, but the collector can't know that yet.
        # Using full identity is always safe: same-identity entries in
        # the same context are true duplicates regardless.
        baseIdentity =
          if isRawEntry then
            nodeIdentity
          else if param.isContextDependent or false then
            nodeIdentity
          else
            den.lib.aspects.fx.identity.stripCtxSuffix nodeIdentity;
        loc = "${param.class}@${baseIdentity}";
        mod =
          if isRawEntry then
            # Store full param for post-pipeline wrapping
            param // { __loc = loc; }
          else
          # Legacy path: construct module location wrapper
          if den.lib.aspects.fx.identity.isAnonIdentity nodeIdentity then
            lib.setDefaultModuleLocation loc param.module
          else
            {
              key = loc;
              _file = loc;
              imports = [ param.module ];
            };
        scope = state.currentScope;
        emittedLocs = (state.scopedEmittedLocs or (_: { })) null;
        scopeLocs = emittedLocs.${scope} or { };
        alreadyEmitted = scopeLocs ? ${loc};
      in
      {
        resume = null;
        state =
          if alreadyEmitted then
            state
          else
            state
            // {
              scopedClassImports =
                x:
                let
                  all = state.scopedClassImports x;
                  scopeData = all.${scope} or { };
                in
                all
                // {
                  ${scope} = scopeData // {
                    ${param.class} = (scopeData.${param.class} or [ ]) ++ [ mod ];
                  };
                };
              scopedEmittedLocs =
                _:
                emittedLocs
                // {
                  ${scope} = scopeLocs // {
                    ${loc} = true;
                  };
                };
            };
      };
  };

  deferredIncludeHandler = {
    "defer-include" =
      { param, state }:
      {
        resume = [ ];
        state = scopedAppend state "scopedDeferredIncludes" state.currentScope param;
      };
  };

  registerAspectPolicyHandler = {
    "register-aspect-policy" =
      { param, state }:
      let
        entry = {
          inherit (param) fn ownerIdentity;
        };
      in
      {
        resume = null;
        state =
          (scopedMerge state "scopedAspectPolicies" state.currentScope {
            ${param.name} = entry;
          })
          // {
            flatAspectPolicies = (state.flatAspectPolicies or { }) // { ${param.name} = entry; };
          };
      };
  };

  drainDeferredHandler = {
    "drain-deferred" =
      { param, state }:
      let
        ctx = param;
        # Read deferred includes from ALL scopes — drain is triggered on
        # context widen and should satisfy deferrals from any ancestor scope.
        allScoped = (state.scopedDeferredIncludes or (_: { })) null;
        allDeferred = lib.concatLists (lib.attrValues allScoped);
      in
      if allDeferred == [ ] then
        {
          resume = [ ];
          inherit state;
        }
      else
        let
          partitioned = lib.partition (
            d: builtins.all (k: builtins.hasAttr k ctx) d.requiredArgs
          ) allDeferred;
          satisfiable = partitioned.right;
          remaining = partitioned.wrong;
          # Remove satisfied items from current scope only, preserve other scopes.
          inherit (state) currentScope;
        in
        {
          resume = satisfiable;
          state = state // {
            scopedDeferredIncludes =
              _:
              allScoped
              // {
                ${currentScope} = remaining;
              };
          };
        };
  };

  registerRouteHandler = {
    "register-route" =
      { param, state }:
      let
        scope = state.currentScope;
        route = param // {
          sourceScopeId = param.sourceScopeId or scope;
        };
        # Dedup key: same route registered from multiple policy dispatch levels.
        routeKey = "${route.fromClass or "?"}>${route.intoClass or "?"}@${route.sourceScopeId}/${
          lib.concatStringsSep "/" (route.path or [ ])
        }";
        registeredRoutes = (state.registeredRouteKeys or (_: { })) null;
        alreadyRegistered = registeredRoutes ? ${routeKey};
      in
      {
        resume = null;
        state =
          if alreadyRegistered then
            state
          else
            scopedAppend state "scopedRoutes" scope route
            // {
              registeredRouteKeys = _: registeredRoutes // { ${routeKey} = true; };
            };
      };
  };

  registerInstantiateHandler = {
    "register-instantiate" =
      { param, state }:
      let
        scope = state.currentScope;
      in
      {
        resume = null;
        state = scopedAppend state "scopedInstantiates" scope (param // { sourceScopeId = scope; });
      };
  };

in
{
  inherit
    scopedAppend
    scopedMerge
    constraintRegistryHandler
    chainHandler
    classCollectorHandler
    registerAspectPolicyHandler
    deferredIncludeHandler
    drainDeferredHandler
    registerRouteHandler
    registerInstantiateHandler
    ;
}
