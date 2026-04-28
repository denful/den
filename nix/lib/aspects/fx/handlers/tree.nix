# constraintRegistryHandler: Handles register-constraint, check-constraint
#   State reads: constraintRegistry, constraintFilters, includesChain
#   State writes: constraintRegistry, constraintFilters
# chainHandler: Handles chain-push, chain-pop
#   State reads/writes: includesChain
#   (stage tracking removed — trace derives entityKind from entries)
# classCollectorHandler: Handles emit-class
#   State reads/writes: classImports
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
        ownerChain = (state.includesChain or (_: [ ])) null;
        scope = param.scope or "subtree";
      in
      if param.type == "filter" then
        {
          resume = null;
          state = state // {
            constraintFilters =
              _:
              ((state.constraintFilters or (_: [ ])) null)
              ++ [
                {
                  predicate = param.predicate;
                  owner = param.owner or "<anon>";
                  inherit scope ownerChain;
                }
              ];
          };
        }
      else
        let
          registry = (state.constraintRegistry or (_: { })) null;
          existing = registry.${param.identity} or [ ];
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
            constraintRegistry =
              _:
              registry
              // {
                ${param.identity} = existing ++ [ entry ];
              };
          };
        };

    "check-constraint" =
      { param, state }:
      let
        nodeIdentity = if builtins.isAttrs param then param.identity else param;
        aspect = if builtins.isAttrs param then param.aspect or null else null;
        registry = (state.constraintRegistry or (_: { })) null;
        filters = (state.constraintFilters or (_: [ ])) null;
        currentChain = (state.includesChain or (_: [ ])) null;
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
      let
        chain = (state.includesChain or (_: [ ])) null;
      in
      {
        resume = null;
        state = state // {
          includesChain = _: chain ++ [ param.identity ];
        };
      };
    "chain-pop" =
      { param, state }:
      let
        chain = (state.includesChain or (_: [ ])) null;
      in
      {
        resume = null;
        state = state // {
          includesChain =
            _:
            if chain == [ ] then
              throw "fx: chain-pop on empty includesChain — push/pop mismatch in aspect compiler"
            else
              lib.init chain;
        };
      };
  };

  classCollectorHandler = {
    "emit-class" =
      { param, state }:
      let
        nodeIdentity = param.identity or "<anon>";
        baseIdentity =
          if param.isContextDependent or false then
            nodeIdentity
          else
            lib.head (lib.splitString "/{" nodeIdentity);
        loc = "${param.class}@${baseIdentity}";
        isAnon =
          !(den.lib.aspects.isMeaningfulName nodeIdentity)
          || lib.hasPrefix "<root>/" nodeIdentity
          || lib.hasInfix "/<anon>:" nodeIdentity;
        mod =
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
          classImports =
            x:
            let
              current = state.classImports x;
            in
            current
            // {
              ${param.class} = (current.${param.class} or [ ]) ++ [ mod ];
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
          deferredIncludes = x: ((state.deferredIncludes or (_: [ ])) x) ++ [ param ];
        };
      };
  };

  registerAspectPolicyHandler = {
    "register-aspect-policy" =
      { param, state }:
      let
        registry = (state.aspectPolicies or (_: { })) null;
        entry = {
          inherit (param) fn ownerIdentity;
        };
      in
      {
        resume = null;
        state = state // {
          aspectPolicies =
            _:
            registry
            // {
              ${param.name} = entry;
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
        traitNames = den.traits or { };

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
        deferred = (state.deferredIncludes or (_: [ ])) null;
      in
      if deferred == [ ] then
        {
          resume = [ ];
          inherit state;
        }
      else
        let
          partitioned = lib.partition (d: builtins.all (k: builtins.hasAttr k ctx) d.requiredArgs) deferred;
          satisfiable = partitioned.right;
          remaining = partitioned.wrong;
        in
        {
          resume = satisfiable;
          state = state // {
            deferredIncludes = _: remaining;
          };
        };
  };

  deadLetterHandler = {
    "dead-letter" =
      { param, state }:
      {
        resume = null;
        state = state // {
          deadLetterQueue = x: (state.deadLetterQueue x) ++ [ param ];
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
    ;
}
