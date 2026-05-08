{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx.identity) aspectPath pathKey;
  inherit (den.lib.aspects) isMeaningfulName;

  # Derive the entity kind for the current node by walking the includes
  # chain upward through accumulated entries to find the nearest ancestor
  # with a non-null entityKind. O(chain × entries) — acceptable for
  # diagnostic-only code path.
  deriveEntityKind =
    state:
    let
      chain = ((state.scopedIncludesChain or (_: { })) null).${state.currentScope} or [ ];
      kindMap = state.entityKindMap or { };
      entries = state.entries or [ ];
      ancestorKinds = lib.filter (s: s != null) (
        map (
          id:
          # Check the kindMap first (populated by resolve-children before
          # children fire), then fall back to entries for cross-entity lookups.
          if kindMap ? ${id} then
            kindMap.${id}
          else
            let
              hit = lib.findFirst (e: (e.path or e.name) == id && e.entityKind != null) null entries;
            in
            if hit != null then hit.entityKind else null
        ) (lib.reverseList chain)
      );
    in
    if ancestorKinds != [ ] then lib.head ancestorKinds else null;

  # Derive parent from includesChain, filtering out self-references.
  # The chain contains raw identity strings from chain-push (pathKey of aspectPath).
  #
  # In structuredTraceHandler: selfPath is the raw pathKey — filter is effective
  # for meaningful nodes whose identity matches a chain entry.
  #
  # In tracingHandler: selfFullPath may be a disambiguated name (e.g.,
  # "host/resolve(desktop):provider") for anonymous nodes. Since anonymous nodes
  # don't push to the chain, the filter is a no-op for them — which is correct.
  # The filter only matters for meaningful (chain-pushing) nodes where
  # selfFullPath == raw pathKey.
  # Find nearest meaningful ancestor in the chain, skipping anonymous
  # intermediates. Falls back to last entry if no meaningful one found.
  chainParent =
    chain: selfPath:
    let
      filtered = builtins.filter (p: p != selfPath) chain;
      meaningful = builtins.filter (
        p: isMeaningfulName p && builtins.match ".*<anon>.*" p == null
      ) filtered;
    in
    if meaningful != [ ] then
      lib.last meaningful
    else if filtered != [ ] then
      lib.last filtered
    else
      null;

  # Shared entry fields for both trace handlers.
  mkBaseEntry = class: param: {
    inherit class;
    provider = param.meta.provider or [ ];
    excluded = param.meta.excluded or false;
    excludedFrom = param.meta.excludedFrom or null;
    replacedBy = param.meta.replacedBy or null;
    isProvider = (param.meta.provider or [ ]) != [ ];
    handlers = param.meta.handleWith or [ ];
    hasClass = param ? ${class};
    isParametric = param.meta.isParametric or false;
    fnArgNames = param.meta.fnArgNames or [ ];
  };

  # Minimal trace handler — accumulates entries without disambiguation.
  # Use for tests that verify basic parent/entry structure.
  # For full tracing with anonymous entry disambiguation, use tracingHandler.
  structuredTraceHandler = class: {
    "resolve-complete" =
      { param, state }:
      let
        selfPath = pathKey (aspectPath param);
        entry = mkBaseEntry class param // {
          name = param.name or "<anon>";
          parent = chainParent (((state.scopedIncludesChain or (_: { })) null).${state.currentScope} or [ ]
          ) selfPath;
          entityKind = param.__entityKind or null;
        };
      in
      {
        resume = param;
        state = state // {
          entries = (state.entries or [ ]) ++ [ entry ];
        };
      };
  };

  # Resolve a human-readable name for an entity kind from scope context.
  resolveEntityName =
    ek: scopeCtx:
    let
      entity = scopeCtx.${ek} or null;
    in
    if entity != null && entity ? name then entity.name else ek;

  # Combined resolve-complete handler for tracing: collects trace entries and paths.
  # Module collection is handled by classCollectorHandler via emit-class effects.
  # Use as extraHandlers with mkPipeline.
  #
  # Disambiguates anonymous entries using entity kind tags, matching the
  # legacy structuredTrace adapter's naming: entityKind/kind(aspect):provider.
  tracingHandler = class: {
    # Record entityKind by identity at resolve time (before children fire),
    # so deriveEntityKind can find ancestors via entityKindMap.
    "resolve" =
      { param, state }:
      let
        ek = param.aspect.__entityKind or null;
        identity = param.identity;
      in
      {
        # Mirror default resolve handler: forward to compile.
        resume = den.lib.fx.send "compile" param;
        state =
          state
          // lib.optionalAttrs (ek != null) {
            entityKindMap = (state.entityKindMap or { }) // {
              ${identity} = ek;
            };
          };
      };
    "resolve-complete" =
      { param, state }:
      let
        rawName = param.meta.originalName or param.name or "<anon>";
        provPath = lib.concatStringsSep "/" (param.meta.provider or [ ]);
        entityKind =
          let
            direct = param.__entityKind or null;
          in
          if direct != null then direct else deriveEntityKind state;
        # Derive ctxAspect from includes chain: nearest meaningful ancestor's
        # base name (strip provider path and ctxId suffix for readability).
        chain = ((state.scopedIncludesChain or (_: { })) null).${state.currentScope} or [ ];
        chainTip = if chain != [ ] then lib.last chain else null;
        ctxAspect =
          if chainTip == null then
            null
          else
            let
              segments = lib.splitString "/" chainTip;
              # Drop {ctxId} suffixes (segments starting with "{").
              base = builtins.filter (s: builtins.match "\\{.*" s == null) segments;
            in
            if base == [ ] then chainTip else lib.last base;
        constraintOwner = param.meta.constraintOwner or null;
        meaningful = n: n != null && isMeaningfulName n && builtins.match ".*<anon>.*" n == null;
        isAnon = !meaningful rawName;
        # Parametric aspects carry fnArgNames (e.g. ["host" "user"]) from the
        # wrapper's formal args.  Use these to label otherwise-anonymous nodes.
        fnArgs = param.meta.fnArgNames or [ ];
        isParametricAnon = isAnon && fnArgs != [ ];
        # Policy-sourced aspects may carry __sourcePolicyName on the param
        # (tagged by classify.nix / apply.nix).
        sourcePolicyName = param.__sourcePolicyName or null;
        name =
          if isAnon && constraintOwner != null then
            "filter:${constraintOwner}"
          else if isAnon && entityKind != null then
            let
              aspectTag = if ctxAspect != null then "(${ctxAspect})" else "";
              provTag = lib.optionalString (provPath != "") ":${provPath}";
            in
            "${entityKind}/resolve${aspectTag}${provTag}"
          else if isAnon && sourcePolicyName != null then
            "policy:${sourcePolicyName}"
          else if isParametricAnon then
            "<parametric:{${lib.concatStringsSep "," fnArgs}}>"
          else
            rawName;
        selfFullPath = if provPath != "" then "${provPath}/${name}" else name;
        scope = state.currentScope;
        scopeCtx = if scope == null then { } else ((state.scopeContexts or (_: { })) null).${scope} or { };
        entityInstance =
          if entityKind != null then "${entityKind}:${resolveEntityName entityKind scopeCtx}" else null;
        entry = mkBaseEntry class param // {
          inherit name entityKind entityInstance;
          parent = chainParent chain selfFullPath;
        };
        isNewKind = !(builtins.any (e: e.key == entityKind) (state.ctxTrace or [ ]));
        ctxEntry = {
          key = entityKind;
          selfName = resolveEntityName entityKind scopeCtx;
          inherit entityKind;
          ctxKeys = builtins.attrNames scopeCtx;
        };
      in
      {
        resume = param;
        state =
          state
          // {
            entries = (state.entries or [ ]) ++ [ entry ];
          }
          // lib.optionalAttrs (entityKind != null && isNewKind) {
            ctxTrace = (state.ctxTrace or [ ]) ++ [ ctxEntry ];
          };
      };
    # Track pipe production: when an aspect emits data for a pipe key.
    "emit-class" =
      { param, state }:
      let
        isPipe = param.__isPipeEntry or false;
        scope = state.currentScope;
      in
      {
        resume = null;
        state =
          state
          // lib.optionalAttrs isPipe {
            pipeProducers = (state.pipeProducers or [ ]) ++ [
              {
                pipeName = param.class;
                aspectIdentity = param.identity;
                inherit scope;
              }
            ];
          };
      };
    # Track pipe consumption: when a policy registers pipe.collect or other pipe effects.
    "register-pipe-effect" =
      { param, state }:
      let
        pipeName = param.value.pipeName or param.pipeName or null;
        stages = param.value.stages or param.stages or [ ];
        hasCollect = builtins.any (s: (s.__pipeStage or null) == "collect") stages;
        scope = state.currentScope;
      in
      {
        resume = null;
        state =
          state
          // lib.optionalAttrs (pipeName != null) {
            pipeConsumers = (state.pipeConsumers or [ ]) ++ [
              {
                inherit pipeName hasCollect scope;
                stageTypes = map (s: s.__pipeStage or "unknown") stages;
              }
            ];
          };
      };
    "record-fired" =
      { param, state }:
      let
        scope = state.currentScope;
        scopeCtx = if scope == null then { } else ((state.scopeContexts or (_: { })) null).${scope} or { };
        entityInstance =
          if param.entityKind != null then
            "${param.entityKind}:${resolveEntityName param.entityKind scopeCtx}"
          else
            null;
        firedNames = builtins.attrNames param.firedPolicies;
        policyEntries = map (policyName: {
          name = policyName;
          class = "";
          parent = null;
          provider = [ ];
          excluded = false;
          excludedFrom = null;
          replacedBy = null;
          isProvider = false;
          handlers = [ ];
          hasClass = false;
          isParametric = false;
          fnArgNames = [ ];
          entityKind = param.entityKind;
          inherit entityInstance;
          isPolicyDispatch = true;
          policyName = policyName;
          from = param.entityKind;
          to = null;
        }) firedNames;
      in
      {
        resume = null;
        state = state // {
          entries = (state.entries or [ ]) ++ policyEntries;
        };
      };
  };

in
{
  inherit structuredTraceHandler tracingHandler;
}
