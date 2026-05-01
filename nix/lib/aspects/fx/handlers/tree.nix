# constraintRegistryHandler: Handles register-constraint, check-constraint
#   State reads: scopedConstraintRegistry, scopedConstraintFilters, scopedIncludesChain
#   State writes: scopedConstraintRegistry, scopedConstraintFilters
# chainHandler: Handles chain-push, chain-pop
#   State reads/writes: scopedIncludesChain
# classCollectorHandler: Handles emit-class
#   State reads/writes: scopedClassImports
{
  lib,
  den,
  ...
}:
let
  # All growing state fields are thunk-wrapped (_: value) so the
  # trampoline's deepSeq doesn't re-materialize them at every step.
  # Unwrap with `(state.field or (_: default)) null`.

  constraintRegistryHandler = {
    "register-constraint" =
      { param, state }:
      let
        currentScope = state.currentScope;
        ownerChain = ((state.scopedIncludesChain or (_: { })) null).${currentScope} or [ ];
        scope = param.scope or "subtree";
      in
      if param.type == "filter" then
        {
          resume = null;
          state = state // {
            scopedConstraintFilters =
              _:
              let
                all = (state.scopedConstraintFilters or (_: { })) null;
                currentScope = state.currentScope;
                existing = all.${currentScope} or [ ];
              in
              all
              // {
                ${currentScope} = existing ++ [
                  {
                    predicate = param.predicate;
                    owner = param.owner or "<anon>";
                    inherit scope ownerChain;
                  }
                ];
              };
          };
        }
      else
        let
          entry = {
            type = param.type;
            getReplacement = param.getReplacement or (_: null);
            owner = param.owner or "<anon>";
            inherit scope ownerChain;
          };
        in
        {
          resume = null;
          state = state // {
            scopedConstraintRegistry =
              _:
              let
                all = (state.scopedConstraintRegistry or (_: { })) null;
                currentScope = state.currentScope;
                scopeData = all.${currentScope} or { };
                existingScoped = scopeData.${param.identity} or [ ];
              in
              all
              // {
                ${currentScope} = scopeData // {
                  ${param.identity} = existingScoped ++ [ entry ];
                };
              };
          };
        };

    "check-constraint" =
      { param, state }:
      let
        nodeIdentity = if builtins.isAttrs param then param.identity else param;
        aspect = if builtins.isAttrs param then param.aspect or null else null;
        currentScope = state.currentScope;
        # Read constraints from ALL scopes — isAncestor filters by ownerChain.
        allScopedRegistry = (state.scopedConstraintRegistry or (_: { })) null;
        registry = builtins.foldl' (
          acc: scopeData:
          lib.zipAttrsWith (_: builtins.concatLists) [
            acc
            scopeData
          ]
        ) { } (builtins.attrValues allScopedRegistry);
        allScopedFilters = (state.scopedConstraintFilters or (_: { })) null;
        filters = lib.concatLists (lib.attrValues allScopedFilters);
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
          mkDecision "exclude" { owner = firstEntry.owner; }
        else if firstEntry.type == "substitute" then
          mkDecision "substitute" {
            replacement = firstEntry.getReplacement null;
            owner = firstEntry.owner;
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
          mkDecision "exclude" { owner = failedFilter.owner; }
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
              currentScope = state.currentScope;
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
              currentScope = state.currentScope;
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
            lib.head (lib.splitString "/{" nodeIdentity);
        loc = "${param.class}@${baseIdentity}";
        mod =
          if isRawEntry then
            # Store full param for post-pipeline wrapping
            param // { __loc = loc; }
          else
            # Legacy path: construct module location wrapper
            let
              isAnon =
                !(den.lib.aspects.isMeaningfulName nodeIdentity)
                || lib.hasPrefix "<root>/" nodeIdentity
                || lib.hasInfix "/<anon>:" nodeIdentity;
            in
            if isAnon then
              lib.setDefaultModuleLocation loc param.module
            else
              {
                key = loc;
                _file = loc;
                imports = [ param.module ];
              };
      in
      {
        resume = null;
        state = state // {
          scopedClassImports =
            x:
            let
              all = state.scopedClassImports x;
              scope = state.currentScope;
              scopeData = all.${scope} or { };
            in
            all
            // {
              ${scope} = scopeData // {
                ${param.class} = (scopeData.${param.class} or [ ]) ++ [ mod ];
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
        state = state // {
          scopedDeferredIncludes =
            x:
            let
              all = (state.scopedDeferredIncludes or (_: { })) x;
              currentScope = state.currentScope;
            in
            all
            // {
              ${currentScope} = (all.${currentScope} or [ ]) ++ [ param ];
            };
        };
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
        state = state // {
          aspectPolicies =
            _:
            let
              registry = (state.aspectPolicies or (_: { })) null;
            in
            registry // { ${param.name} = entry; };
          scopedAspectPolicies =
            _:
            let
              all = (state.scopedAspectPolicies or (_: { })) null;
              currentScope = state.currentScope;
              scopeData = all.${currentScope} or { };
            in
            all
            // {
              ${currentScope} = scopeData // {
                ${param.name} = entry;
              };
            };
        };
      };
  };

  # Dispatch include-only aspect-included policies during tree-walk.
  # Called by emitTransitions BEFORE into-transition so injected aspects
  # participate in entity resolution (visible to class forwarding sub-pipelines).
  #
  # Only processes policies that return NO resolve effects (include/exclude only).
  # PolicyFns with resolve effects are handled by dispatchAspectPolicies in
  # transition.nix — their includes travel with the transition's routing.aspects
  # so they're injected into the child entity's resolution scope.
  # Dispatch include-only aspect-included policies during tree-walk.
  # Called by emitTransitions BEFORE into-transition so injected aspects
  # participate in entity resolution (visible to class forwarding sub-pipelines).
  #
  # Only processes policies that return NO resolve effects (include/exclude only).
  # PolicyFns with resolve effects are handled by dispatchAspectPolicies in
  # transition.nix — their includes travel with the transition's routing.aspects.
  #
  # No dedup tracking: include-only policies must fire for every entity context
  # (e.g., per-user). Cross-level double-firing is prevented by arg matching —
  # a { host, user } policyFn won't match at host level where user is absent.
  dispatchPolicyIncludesHandler = {
    "dispatch-policy-includes" =
      { param, state }:
      let
        aspectPolicies = (state.aspectPolicies or (_: { })) null;
        traits = (state.traits or (_: { })) null;
        currentCtx = param.ctx;
        resolveCtx = traits // currentCtx;
        traitNames = state.traitSchemas null;

        entries = lib.attrsToList aspectPolicies;
        matching = builtins.filter (
          e:
          let
            fargs = den.lib.policyTypes.policyFnArgs e.value.fn;
            requiredArgs = builtins.filter (k: !fargs.${k}) (builtins.attrNames fargs);
          in
          builtins.all (k: resolveCtx ? ${k} || traitNames ? ${k}) requiredArgs
        ) entries;

        # Call matching policies, keep only include-only results.
        perPolicy = map (
          entry:
          let
            rawEffects = entry.value.fn resolveCtx;
            effects = if builtins.isList rawEffects then rawEffects else [ rawEffects ];
            hasResolve = builtins.any (
              e: builtins.isAttrs e && (e.__policyEffect or "") == "resolve" && e.value != { }
            ) effects;
          in
          {
            inherit effects hasResolve;
          }
        ) matching;

        includeOnly = builtins.filter (p: !p.hasResolve) perPolicy;

        allEffects = lib.concatMap (
          p:
          builtins.filter (
            e:
            builtins.isAttrs e
            && builtins.elem (e.__policyEffect or "") [
              "include"
              "exclude"
            ]
          ) p.effects
        ) includeOnly;

        includes = map (e: e.value) (builtins.filter (e: e.__policyEffect == "include") allEffects);
        excludes = map (e: e.value) (builtins.filter (e: e.__policyEffect == "exclude") allEffects);
      in
      {
        resume = { inherit includes excludes; };
        inherit state;
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
          # Put remaining back into current scope (all satisfied ones removed).
          currentScope = state.currentScope;
        in
        {
          resume = satisfiable;
          state = state // {
            scopedDeferredIncludes = _: { ${currentScope} = remaining; };
          };
        };
  };

  deadLetterHandler = {
    "dead-letter" =
      { param, state }:
      {
        resume = null;
        state = state // {
          scopedDeadLetterQueue =
            _:
            let
              all = (state.scopedDeadLetterQueue or (_: { })) null;
              currentScope = state.currentScope;
            in
            all
            // {
              ${currentScope} = (all.${currentScope} or [ ]) ++ [ param ];
            };
        };
      };
  };

  registerTraitSchemaHandler = {
    "register-trait-schema" =
      { param, state }:
      let
        current = state.traitSchemas null;
      in
      {
        resume = null;
        state = state // {
          traitSchemas = _: current // { ${param.name} = param.schema; };
        };
      };
  };

  getTraitSchemasHandler = {
    "get-trait-schemas" =
      { param, state }:
      {
        resume = state.traitSchemas null;
        inherit state;
      };
  };

  registerRouteHandler = {
    "register-route" =
      { param, state }:
      let
        scope = state.currentScope;
        route = param // {
          sourceScopeId = scope;
        };
      in
      {
        resume = null;
        state = state // {
          scopedRoutes =
            _:
            let
              all = state.scopedRoutes null;
            in
            all
            // {
              ${scope} = (all.${scope} or [ ]) ++ [ route ];
            };
        };
      };
  };

  registerInstantiateHandler = {
    "register-instantiate" =
      { param, state }:
      let
        scope = state.currentScope;
        spec = param // {
          sourceScopeId = scope;
        };
      in
      {
        resume = null;
        state = state // {
          scopedInstantiates =
            _:
            let
              all = state.scopedInstantiates null;
            in
            all
            // {
              ${scope} = (all.${scope} or [ ]) ++ [ spec ];
            };
        };
      };
  };

in
{
  inherit
    constraintRegistryHandler
    chainHandler
    classCollectorHandler
    registerAspectPolicyHandler
    dispatchPolicyIncludesHandler
    deferredIncludeHandler
    drainDeferredHandler
    deadLetterHandler
    registerTraitSchemaHandler
    getTraitSchemasHandler
    registerRouteHandler
    registerInstantiateHandler
    ;
}
