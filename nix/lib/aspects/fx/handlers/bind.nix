# Handles: bind
# Probes scope handlers for required args, calls compileFn or defers.
{
  den,
  lib,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) argClass;
  schema = den.schema or { };
  isEntityKind = argClass.isEntityKind schema;
in
{
  bindHandler = {
    "bind" =
      { param, state }:
      let
        inherit (param) aspect compileFn;
        # Entity intermediates already fanned earlier in this chain (e.g. `pet`
        # when fanning `toy` under `{ pet, toy }`). Threaded through the recursive
        # fan so a transitive descendant can enumerate off its immediate parent.
        boundEntities = param.boundEntities or { };
        childArgs = aspect.__args or { };
        childScopeHandlers = aspect.__scopeHandlers or { };
        requiredKeys = builtins.filter (k: !childArgs.${k}) (builtins.attrNames childArgs);
        keysToProbe = builtins.filter (k: !(childScopeHandlers ? ${k})) requiredKeys;
        # Fallback: check current scope's context from pipeline state.
        # scope.provide doesn't survive handler boundaries, but the scope
        # context in state always reflects what's available at the current scope.
        # Only use at non-root scopes — root scope handlers work via the pipeline.
        currentScope = state.currentScope or null;
        rootScopeId = state.rootScopeId or null;
        isChildScope = currentScope != null && rootScopeId != null && currentScope != rootScopeId;
        scopeCtx =
          if isChildScope then
            let
              ctxs = (state.scopeContexts or (_: { })) null;
              entityCls = ((state.scopeEntityClass or (_: { })) null).${currentScope} or null;
            in
            (ctxs.${currentScope} or { }) // lib.optionalAttrs (entityCls != null) { class = entityCls; }
          else
            { };
        keysAfterStateFallback = builtins.filter (k: !(scopeCtx ? ${k})) keysToProbe;
        # Entity records reachable for descendant child-enumeration: the scope's
        # own ctx (scope + ancestors) plus intermediates fanned earlier in this
        # chain. A transitive descendant enumerates off its IMMEDIATE parent
        # record, which may be a fanned intermediate rather than the scope root.
        availRecords = scopeCtx // boundEntities;
        # Detect pipe arg references: if any required keys are pipe names,
        # unconditionally defer — pipe data is assembled post-pipeline.
        pipeRegistry = den.quirks or { };
        hasPipeArgs = builtins.any (k: pipeRegistry ? ${k}) requiredKeys;
        # Augment __scopeHandlers with ALL requested keys available in scope
        # context (both required and optional).  This ensures scope.provide
        # values (host, user, class) override pipeline-level defaults even
        # for optional args.
        allRequestedKeys = builtins.attrNames childArgs;
        scopeOverrideKeys = builtins.filter (
          k: !(childScopeHandlers ? ${k}) && scopeCtx ? ${k}
        ) allRequestedKeys;
        augmentedAspect =
          if scopeOverrideKeys != [ ] then
            let
              stateHandlers = den.lib.aspects.fx.handlers.constantHandler (
                builtins.listToAttrs (
                  map (k: {
                    name = k;
                    value = scopeCtx.${k};
                  }) scopeOverrideKeys
                )
              );
            in
            aspect
            // {
              __scopeHandlers = childScopeHandlers // stateHandlers;
            }
          else
            aspect;
        # Kind of the entity that owns the current scope (K_S), from state.
        scopeKind =
          if currentScope == null then
            null
          else
            ((state.scopeEntityKind or (_: { })) null).${currentScope} or null;
        inherit (den.lib.aspects.fx) identity;
        # Per-scope include ancestry of the aspect currently binding. Element 0
        # is the entity-kind root (== scopeKind); element 1 is the schema-include
        # node that delivered this aspect into the current scope (its identity
        # key). Deeper elements are nested sub-includes — the PROVENANCE ROOT we
        # care about stays at index 1 regardless of nesting depth.
        scopeChain = ((state.scopedIncludesChain or (_: { })) null).${currentScope} or [ ];
        # identity.key of the schema-include node this aspect descends from, or
        # null if the aspect isn't a schema-include descendant (e.g. the entity
        # self-aspect with an empty/length-1 chain).
        aspectIncludeRoot = if builtins.length scopeChain >= 2 then builtins.elemAt scopeChain 1 else null;
        # True when the SAME schema-include node that delivered this aspect into
        # the current (ancestor) scope is ALSO registered in `argKind`'s own
        # schema includes — i.e. one source injected at both the ancestor AND the
        # descendant entity kind (e.g. `den.default`, registered into
        # schema.{host,user,home}.includes). Such an aspect reaches the
        # descendant directly via its own scope's resolution, so fanning it out
        # at the ancestor here would double-cover; it is inert at the ancestor.
        #
        # Structural-identity comparison: matches on identity.key of the include
        # NODE (the provenance root captured in scopedIncludesChain), NOT a
        # head-of-display-name string. This kills the false positive on
        # coincidental name collisions and the false negative on nested include
        # chains that the old `splitString aspect.name` heuristic carried —
        # `chain[1]` is the schema-include root at any nesting depth, and
        # identity.key is the same stable key both lists register the node under
        # (den.default appears as the same value → same key in each).
        sharedWithDescendant =
          argKind:
          let
            descIncludes = (schema.${argKind} or { }).includes or [ ];
          in
          aspectIncludeRoot != null && builtins.any (inc: identity.key inc == aspectIncludeRoot) descIncludes;
        # Per-key probe: which required keys have NO handler anywhere.
        probeMissing =
          keys:
          builtins.foldl' (
            acc: key:
            fx.bind acc (
              missing:
              fx.bind (fx.effects.hasHandler key) (
                isAvailable: fx.pure (missing ++ lib.optionals (!isAvailable) [ key ])
              )
            )
          ) (fx.pure [ ]) keys;
        # Fan out over the scope's K_a-children for descendant entity-arg
        # argKind, refiring `bind` bound to each child. Recursion on "bind"
        # discovers further descendant args per child → cartesian for free.
        # All instances EMIT AT THE CURRENT SCOPE.
        fanOut =
          argKind:
          let
            # Enumerate children off argKind's PARENT-kind record (host.users,
            # pet.toys), not the scope root — so a transitive descendant chains
            # through its immediate parent. The parent record is whichever of the
            # scope ctx / a fanned intermediate carries that kind.
            parentKind = argClass.parentKindOf schema scopeKind argKind;
            parentRecord = if parentKind == null then null else availRecords.${parentKind} or null;
            children = if parentRecord == null then [ ] else argClass.childrenOf parentRecord argKind;
            bindChild =
              idx: child:
              fx.send "bind" {
                aspect = augmentedAspect // {
                  __scopeHandlers =
                    (augmentedAspect.__scopeHandlers or { })
                    // den.lib.aspects.fx.handlers.constantHandler { ${argKind} = child; };
                  __ctxId = "${
                    augmentedAspect.__ctxId or augmentedAspect.name or "fanout"
                  }@${argKind}=${child.name or (toString idx)}";
                  # All fan-out instances emit at the SAME (emitting) scope, so
                  # per-scope dedup can't keep them apart. Force context
                  # dependence so emit-class keys each by its ctx-qualified
                  # identity (preserving the {ctxId} suffix) rather than
                  # collapsing siblings to a shared base identity.
                  meta = (augmentedAspect.meta or { }) // {
                    contextDependent = true;
                  };
                };
                inherit compileFn;
                # Record this intermediate so a deeper descendant's fan reads its
                # children off THIS record (transitive DAG nesting).
                boundEntities = boundEntities // {
                  ${argKind} = child;
                };
              };
            # Fold child binds, collecting r.value singletons ++ r.fanOut lists.
            collect = builtins.foldl' (
              acc: i:
              fx.bind acc (
                vals:
                fx.bind (bindChild i (builtins.elemAt children i)) (
                  r: fx.pure (vals ++ (r.fanOut or (lib.optional (r ? value) r.value)))
                )
              )
            ) (fx.pure [ ]) (lib.genList lib.id (builtins.length children));
          in
          if children == [ ] then
            fx.pure { inert = true; }
          else
            fx.bind collect (vals: fx.pure { fanOut = vals; });
      in
      {
        resume = fx.bind (probeMissing keysAfterStateFallback) (
          missingKeys:
          if missingKeys == [ ] then
            fx.bind (compileFn augmentedAspect) (result: fx.pure { value = result; })
          else
            let
              # Entity classification (the formal rule). An entity-kind missing
              # arg at scope S (kind K_S) is: in-ctx (handled upstream, not
              # missing) → descendant of K_S → fan out at S → otherwise MISPLACED
              # → whole aspect inert, silently.
              #
              # Root scope (scopeKind == null) has NO entity kind: isDescendantOf
              # is false for a null scopeKind, so every entity arg here is
              # misplaced → inert. (The old cross-scope defer carrier is gone; a
              # root defer would dangle forever — inert is the rule's verdict.)
              entityMissing = builtins.filter isEntityKind missingKeys;
              descendants = builtins.filter (argClass.isDescendantOf schema scopeKind) entityMissing;
              misplaced = builtins.filter (k: !(builtins.elem k descendants)) entityMissing;
            in
            # An entity arg that is neither in-ctx nor a descendant → inert.
            # Silent here by design, but the verdict is recorded: a TERMINAL
            # walk (resolve.nix's post-assembly drain) has no later scope to
            # deliver at, and reads this residue to tell a vanished delivery
            # from an aspect that legitimately emits nothing. The other two
            # inert verdicts stay unrecorded on purpose — zero children has no
            # target to deliver to, and the shared-with-descendant case is
            # double-cover avoidance, where the descendant does receive it.
            if misplaced != [ ] then
              fx.bind (fx.send "record-inert" {
                aspect = aspect.name or "<anon>";
                args = misplaced;
              }) (_: fx.pure { inert = true; })
            # First descendant arg fans out — unless the same source is also
            # injected at the descendant kind (e.g. den.default), in which case
            # it reaches the descendant directly and fanning out here would
            # double-cover; such an aspect is inert at this scope.
            else if descendants != [ ] then
              (
                let
                  # Fan a descendant whose parent kind is reachable NOW (the scope
                  # itself or an already-fanned intermediate); the recursion fans
                  # deeper descendants once their parent is bound. Shallowest-first,
                  # NOT alphabetical — a transitive chain must bind the intermediate
                  # before its child (`{ pet, toy }`: fan `pet`, then `toy` off it).
                  fanable = argClass.fanableDescendants schema scopeKind availRecords descendants;
                  pick = if fanable != [ ] then builtins.head fanable else builtins.head descendants;
                in
                if sharedWithDescendant pick then fx.pure { inert = true; } else fanOut pick
              )
            # Only non-entity (pipe/conditional/enrichment) args remain → defer.
            else
              fx.bind (fx.send "defer" {
                child = aspect;
                inherit requiredKeys;
                requiredArgs = missingKeys;
                inherit hasPipeArgs;
              }) (_: fx.pure { deferred = true; })
        );
        inherit state;
      };
  };
}
