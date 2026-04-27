# constraintRegistryHandler: Handles register-constraint, check-constraint
#   State reads: constraintRegistry, constraintFilters, includesChain
#   State writes: constraintRegistry, constraintFilters
# chainHandler: Handles chain-push, chain-pop
#   State reads/writes: includesChain
#   (stage tracking removed — trace derives entityKind from entries)
# classCollectorHandler: Handles emit-class
#   State reads/writes: imports
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

  classCollectorHandler =
    {
      targetClass,
    }:
    {
      "emit-class" =
        { param, state }:
        if param.class != targetClass then
          {
            resume = null;
            inherit state;
          }
        else
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
              imports = x: (state.imports x) ++ [ mod ];
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

in
{
  inherit
    constraintRegistryHandler
    chainHandler
    classCollectorHandler
    registerAspectPolicyHandler
    deferredIncludeHandler
    drainDeferredHandler
    ;
}
