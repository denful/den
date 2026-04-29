{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  identity = den.lib.aspects.fx.identity;
  inherit (den.lib.aspects.fx.handlers) constantHandler emitCrossProvideShims;
  inherit (den.lib.aspects) isParametricWrapper isMeaningfulName;

  structuralKeysSet = lib.genAttrs [
    "name"
    "description"
    "meta"
    "includes"
    "provides"
    "policies"
    "policies"
    "into"
    "traits"
    "classes"
    "__fn"
    "__args"
    "__functor"
    "__functionArgs"
    "__scopeHandlers"
    "__ctxId"
    "__entityKind"
    "__parametricResolved"
    "_module"
    "_"
  ] (_: true);

  # Resolve collision policy from three levels: aspect meta → entity → global.
  # Shared by wrapClassModule (specialArgs collisions) and mkCollisionDetector
  # (_module.args collisions).
  resolveCollisionPolicy =
    {
      ctx,
      aspectPolicy,
      globalPolicy,
    }:
    name:
    if aspectPolicy != null then
      aspectPolicy
    else if
      builtins.isAttrs (ctx.${name} or null)
      && (ctx.${name} ? collisionPolicy)
      && ctx.${name}.collisionPolicy != null
    then
      ctx.${name}.collisionPolicy
    else
      globalPolicy;

  # Class modules (after aspectContentType unwrapping or from deferred
  # imports) may be { imports = [...]; } attrsets. The original function
  # is nested inside.  We recursively descend into imports to find and
  # wrap any functions that request den context args.
  wrapDeferredImports =
    args: imports:
    let
      go =
        imp:
        if builtins.isFunction imp then
          let
            result = wrapClassModule (args // { module = imp; });
          in
          {
            inherit (result) wrapped;
            value = result.module;
          }
        else if builtins.isAttrs imp && imp ? imports then
          let
            inner = map go imp.imports;
            anyWrapped = builtins.any (r: r.wrapped) inner;
          in
          {
            wrapped = anyWrapped;
            value = imp // {
              imports = map (r: r.value) inner;
            };
          }
        else
          {
            wrapped = false;
            value = imp;
          };
      results = map go imports;
      anyWrapped = builtins.any (r: r.wrapped) results;
    in
    {
      wrapped = anyWrapped;
      imports = map (r: r.value) results;
    };

  wrapClassModule =
    {
      module,
      ctx,
      aspectPolicy,
      globalPolicy,
      traitNames ? { },
    }:
    if builtins.isAttrs module && module ? imports then
      let
        result = wrapDeferredImports {
          inherit
            ctx
            aspectPolicy
            globalPolicy
            traitNames
            ;
        } module.imports;
        policy = resolveCollisionPolicy { inherit ctx aspectPolicy globalPolicy; };
        denArgNames = builtins.attrNames ctx;
        advertisedArgs = lib.genAttrs denArgNames (_: true);
        validatorAdvertisedArgs = {
          config = true;
        };
        validator =
          moduleArgs:
          let
            collisionChecks = lib.concatMap (
              name:
              let
                mArgs = moduleArgs.config._module.args or { };
                hasReal =
                  (builtins.tryEval (builtins.seq (mArgs.${name} or null) (mArgs ? ${name}))).value or false;
                p = policy name;
              in
              if !hasReal then
                [ ]
              else if p == "error" then
                throw "den: class module arg '${name}' collides with module-system arg — set collisionPolicy to resolve"
              else if p == "class-wins" then
                [
                  "den: class module arg '${name}' collision — class-wins, den value dropped"
                ]
              else
                [
                  "den: class module arg '${name}' collision — den-wins, module-system value shadowed"
                ]
            ) denArgNames;
          in
          {
            warnings = collisionChecks;
          };
      in
      {
        module = module // {
          imports = result.imports;
        };
        inherit (result) wrapped;
      }
      // lib.optionalAttrs (result.wrapped && ctx != { }) {
        inherit validator validatorAdvertisedArgs advertisedArgs;
      }
    else if !builtins.isFunction module then
      {
        inherit module;
        wrapped = false;
      }
    else
      let
        allArgs = builtins.functionArgs module;
        argNames = builtins.attrNames allArgs;
        denArgNames = builtins.filter (k: ctx ? ${k}) argNames;
        # Trait args: registered trait names not shadowed by ctx.
        traitArgNames = builtins.filter (k: traitNames ? ${k} && !(ctx ? ${k})) argNames;
        # Only warn for args matching known schema kinds that have no default.
        # Avoids false warnings on module-system args (config, pkgs, etc.).
        schemaKinds = builtins.filter (n: n != "conf" && n != "aspect" && !(lib.hasPrefix "_" n)) (
          builtins.attrNames (den.schema or { })
        );
        missingDenArgNames = builtins.filter (k: builtins.elem k schemaKinds && !(allArgs.${k} or false)) (
          builtins.filter (k: !(ctx ? ${k})) argNames
        );
        # Emit warnings for missing den args (matching schema kinds, no default)
        # regardless of whether other den args are found.
        warnedModule = builtins.foldl' (
          mod: k: lib.warn "den: class module requests '${k}' but no ${k} context is available" mod
        ) module missingDenArgNames;
        hasMissingDenArgs = missingDenArgNames != [ ];
      in
      if hasMissingDenArgs then
        {
          module = warnedModule;
          wrapped = false;
          unsatisfied = true;
          missingArgs = missingDenArgNames;
        }
      else if denArgNames == [ ] && traitArgNames == [ ] then
        {
          module = warnedModule;
          wrapped = false;
        }
      else
        let
          denArgs = lib.genAttrs denArgNames (k: ctx.${k});
          remainingArgs = removeAttrs allArgs (denArgNames ++ traitArgNames);
        in
        # Full application: all functionArgs are den args + trait args (no module-system args).
        # Trait args need eval-time resolution, so only fully apply when there are no trait args.
        if remainingArgs == { } && traitArgNames == [ ] then
          {
            module = warnedModule denArgs;
            wrapped = true;
          }
        else
          let
            policy = resolveCollisionPolicy { inherit ctx aspectPolicy globalPolicy; };
            # G(X): the actual module wrapper. Merge order depends on policy.
            # For class-wins args, moduleArgs shadows denArgs (class value used).
            # For den-wins/error args, denArgs shadows moduleArgs (NixOS thunks
            # shadowed without evaluation).
            classWinsNames = builtins.filter (name: policy name == "class-wins") denArgNames;
            classWinsDen = lib.genAttrs classWinsNames (k: denArgs.${k});
            denWinsDen = removeAttrs denArgs classWinsNames;
            # Trait args are resolved lazily from config._den.traits at eval time.
            traitThunks = lib.genAttrs traitArgNames (
              name: moduleArgs: moduleArgs.config._den.traits.${name} or [ ]
            );
            wrapper =
              moduleArgs:
              # class-wins args: den first, then moduleArgs shadows
              # den-wins/error args: moduleArgs first, then denArgs shadows
              # trait args: lazy thunks from config._den.traits
              warnedModule (
                classWinsDen // moduleArgs // denWinsDen // lib.mapAttrs (_: thunk: thunk moduleArgs) traitThunks
              );
            # Validate(X): collision detector. Only advertises module-system
            # args + config. Checks den arg collisions by probing
            # config._module.args rather than advertising den args (which
            # fails when the class module system lacks those keys).
            validatorAdvertisedArgs = remainingArgs // {
              config = true;
            };
            validator =
              moduleArgs:
              let
                collisionChecks = lib.concatMap (
                  name:
                  let
                    # Probe _module.args for den arg names — a collision means
                    # both den and the module system provide the same key.
                    mArgs = moduleArgs.config._module.args or { };
                    hasReal =
                      (builtins.tryEval (builtins.seq (mArgs.${name} or null) (mArgs ? ${name}))).value or false;
                    p = policy name;
                  in
                  if !hasReal then
                    [ ]
                  else if p == "error" then
                    throw "den: class module arg '${name}' collides with module-system arg — set collisionPolicy to resolve"
                  else if p == "class-wins" then
                    [
                      "den: class module arg '${name}' collision — class-wins, den value dropped"
                    ]
                  else
                    [
                      "den: class module arg '${name}' collision — den-wins, module-system value shadowed"
                    ]
                ) denArgNames;
              in
              {
                warnings = collisionChecks;
              };
            # Wrapper advertises den args + trait args so NixOS passes thunks
            # (shadowed lazily by den values without evaluation).
            advertisedArgs = remainingArgs // lib.genAttrs (denArgNames ++ traitArgNames) (_: true);
          in
          {
            module = lib.setFunctionArgs wrapper advertisedArgs;
            # Validator emitted separately via emitClasses
            inherit validator validatorAdvertisedArgs;
            wrapped = true;
          };

  # Reconstruct ctx from scope handlers. constantHandler maps each key
  # to { param, state }: { resume = value; inherit state; }, so invoking
  # with dummy args extracts the original value. This works for all
  # aspects in the tree (not just stage roots) since __scopeHandlers
  # propagates to children, unlike __ctx which only exists on roots.
  ctxFromHandlers =
    handlers:
    lib.mapAttrs (
      _: handler:
      (handler {
        param = null;
        state = { };
      }).resume
    ) handlers;

  # Schema registries for 4-step key classification.
  # Top-level den.classes/den.traits live outside den.schema, breaking
  # the evaluation cycle that existed when they lived inside den.schema.
  classRegistry = den.classes or { };
  traitRegistry = den.traits or { };

  # Classify non-structural keys using the schema registry.
  # 4-step: class → trait → nested aspect → unregistered class.
  # When both registries are empty (no batteries), fall back to treating
  # all non-structural keys as classes for backward compatibility.
  classifyKeys =
    targetClass: aspect:
    let
      allKeys = builtins.filter (k: !(structuralKeysSet ? ${k})) (builtins.attrNames aspect);
      isEmpty = classRegistry == { } && traitRegistry == { };
    in
    if isEmpty then
      {
        classKeys = allKeys;
        traitKeys = [ ];
        nestedKeys = [ ];
        unregisteredClassKeys = [ ];
      }
    else
      let
        partition =
          builtins.foldl'
            (
              acc: k:
              if classRegistry ? ${k} || (targetClass != null && k == targetClass) then
                acc // { classKeys = acc.classKeys ++ [ k ]; }
              else if traitRegistry ? ${k} then
                acc // { traitKeys = acc.traitKeys ++ [ k ]; }
              else
                let
                  rawValue = aspect.${k};
                  # Unwrap aspectContentType to inspect sub-keys.
                  # Multi-site defs: merge all attrset values for detection.
                  innerValue =
                    if builtins.isAttrs rawValue && rawValue ? __contentValues then
                      let
                        vals = map (d: d.value) rawValue.__contentValues;
                        attrVals = builtins.filter builtins.isAttrs vals;
                      in
                      if attrVals != [ ] then builtins.foldl' (a: b: a // b) { } attrVals else null
                    else if builtins.isAttrs rawValue then
                      rawValue
                    else
                      null;
                  # Check if any sub-key is a registered class/trait, or if any
                  # sub-key is itself an attrset containing recognized keys
                  # (multi-level nesting detection, depth-limited to 3).
                  hasRecognizedSubKeysAt =
                    depth: val:
                    builtins.isAttrs val
                    && builtins.any (
                      sk:
                      classRegistry ? ${sk}
                      || traitRegistry ? ${sk}
                      || (depth > 0 && hasRecognizedSubKeysAt (depth - 1) (val.${sk}))
                    ) (builtins.attrNames val);
                  hasRecognizedSubKeys = hasRecognizedSubKeysAt 3 innerValue;
                in
                if hasRecognizedSubKeys then
                  acc // { nestedKeys = acc.nestedKeys ++ [ k ]; }
                else
                  # Unknown key with no recognized sub-keys — treat as class
                  # (backward compat) but emit trace warning for future migration.
                  acc // { unregisteredClassKeys = acc.unregisteredClassKeys ++ [ k ]; }
            )
            {
              classKeys = [ ];
              traitKeys = [ ];
              nestedKeys = [ ];
              unregisteredClassKeys = [ ];
            }
            allKeys;
      in
      partition;

  emitTraits =
    aspect: traitKeys: nodeIdentity:
    fx.seq (
      lib.concatMap (
        k:
        let
          wrapped = aspect.${k};
          contentValues =
            if builtins.isAttrs wrapped && wrapped ? __contentValues then
              wrapped.__contentValues
            else
              [
                {
                  value = wrapped;
                  file = "<unknown>";
                }
              ];
        in
        map (
          cv:
          fx.send "emit-trait" {
            trait = k;
            inherit (cv) value;
            chain = nodeIdentity;
          }
        ) contentValues
      ) traitKeys
    );

  emitClassFromDLQ =
    entry:
    let
      rawValue = entry.rawValue;
      modules =
        if builtins.isList rawValue then
          rawValue
        else if builtins.isAttrs rawValue && rawValue ? __contentValues then
          let
            vals = map (d: d.value) rawValue.__contentValues;
          in
          if builtins.length vals == 1 then [ (builtins.head vals) ] else [ { imports = vals; } ]
        else
          [ rawValue ];
      indexed = lib.imap0 (idx: module: { inherit idx module; }) modules;
      isMulti = builtins.length modules > 1;
    in
    lib.concatMap (
      { idx, module }:
      let
        elemIdentity = if isMulti then "${entry.aspectIdentity}[${toString idx}]" else entry.aspectIdentity;
      in
      [
        (fx.send "emit-class" {
          class = entry.key;
          identity = elemIdentity;
          inherit module;
          ctx = entry.ctx;
          aspectPolicy = entry.aspectPolicy;
          globalPolicy = entry.globalPolicy;
          traitNames = traitRegistry;
          __rawEntry = true;
          isContextDependent = entry.parametricResolved || entry.contextDependent;
        })
      ]
    ) indexed;

  emitTraitFromDLQ =
    entry:
    let
      rawValue = entry.rawValue;
      contentValues =
        if builtins.isAttrs rawValue && rawValue ? __contentValues then
          rawValue.__contentValues
        else
          [
            {
              value = rawValue;
              file = "<unknown>";
            }
          ];
    in
    map (
      cv:
      fx.send "emit-trait" {
        trait = entry.key;
        inherit (cv) value;
        chain = entry.aspectIdentity;
      }
    ) contentValues;

  drainDeadLettersHandler = {
    "drain-dead-letters" =
      { param, state }:
      let
        queue = (state.deadLetterQueue or (_: [ ])) null;
      in
      if queue == [ ] then
        {
          resume = null;
          inherit state;
        }
      else
        let
          classified = builtins.partition (
            entry: classRegistry ? ${entry.key} || traitRegistry ? ${entry.key}
          ) queue;
          matched = classified.right;
          remaining = classified.wrong;
          reEmits = lib.concatMap (
            entry: if classRegistry ? ${entry.key} then emitClassFromDLQ entry else emitTraitFromDLQ entry
          ) matched;
        in
        {
          resume = fx.seq reEmits;
          state = state // {
            deadLetterQueue = _: remaining;
          };
        };
  };

  emitClasses =
    aspect: classKeys: nodeIdentity:
    let
      ctx = ctxFromHandlers (aspect.__scopeHandlers or { });
      aspectPolicy = aspect.meta.collisionPolicy or null;
      globalPolicy = den.config.classModuleCollisionPolicy or "error";
    in
    fx.seq (
      lib.concatMap (
        k:
        let
          rawValue = aspect.${k};
          # aspectContentType wraps values with __contentValues/__provider.
          # Unwrap to recover the original module value for wrapClassModule.
          # Lists are coerced to per-element processing; bare values become singletons.
          modules =
            if builtins.isList rawValue then
              rawValue
            else if builtins.isAttrs rawValue && rawValue ? __contentValues then
              let
                vals = builtins.filter (v: !(builtins.isAttrs v && v == { })) (
                  map (d: d.value) rawValue.__contentValues
                );
              in
              if builtins.length vals == 0 then
                [ { } ]
              else if builtins.length vals == 1 then
                [ (builtins.head vals) ]
              else
                [ { imports = vals; } ]
            else
              [ rawValue ];
          # Process each module element independently.
          indexed = lib.imap0 (idx: module: { inherit idx module; }) modules;
          isMulti = builtins.length modules > 1;
        in
        lib.concatMap (
          { idx, module }:
          let
            elemIdentity = if isMulti then "${nodeIdentity}[${toString idx}]" else nodeIdentity;
          in
          [
            (fx.send "emit-class" {
              class = k;
              identity = elemIdentity;
              inherit
                module
                ctx
                aspectPolicy
                globalPolicy
                ;
              traitNames = traitRegistry;
              __rawEntry = true;
              isContextDependent =
                (aspect.__parametricResolved or false) || (aspect.meta.contextDependent or false);
            })
          ]
        ) indexed
      ) classKeys
    );

  registerConstraints =
    aspect:
    let
      rawHandleWith = aspect.meta.handleWith or null;
      rawExcludes = aspect.meta.excludes or [ ];
      handleWithList =
        if rawHandleWith == null then
          [ ]
        else if builtins.isList rawHandleWith then
          rawHandleWith
        else if builtins.isAttrs rawHandleWith then
          [ rawHandleWith ]
        else
          [ ];
      excludeList = map (ref: {
        type = "exclude";
        scope = "subtree";
        identity = identity.pathKey (identity.aspectPath ref);
      }) rawExcludes;
      allConstraints = handleWithList ++ excludeList;
      owner = aspect.name or "<anon>";
    in
    fx.seq (map (c: fx.send "register-constraint" (c // { inherit owner; })) allConstraints);

  # Fold includes through emit-include effects, tagging each with its
  # positional index and parent __scopeHandlers so the handler
  # can derive stable identities and propagate context to children.
  emitIncludes =
    {
      __parentScopeHandlers ? null,
      __parentCtxId ? null,
    }:
    incs:
    let
      len = builtins.length incs;
      go =
        idx: acc:
        if idx >= len then
          acc
        else
          go (idx + 1) (
            fx.bind acc (
              results:
              fx.bind (fx.send "emit-include" (
                {
                  child = builtins.elemAt incs idx;
                  inherit idx;
                }
                // lib.optionalAttrs (__parentScopeHandlers != null) { inherit __parentScopeHandlers; }
                // lib.optionalAttrs (__parentCtxId != null) { inherit __parentCtxId; }
              )) (childResults: fx.pure (results ++ childResults))
            )
          );
    in
    go 0 (fx.pure [ ]);

  # Dispatch policy include/exclude effects during tree-walk, BEFORE
  # transitions. This ensures injected aspects participate in entity
  # resolution and are visible to class forwarding sub-pipelines (HM forward).
  dispatchPolicyIncludes =
    aspect:
    let
      isEntityRoot = aspect ? __entityKind;
    in
    if !isEntityRoot then
      fx.pure [ ]
    else
      let
        ctx = ctxFromHandlers (aspect.__scopeHandlers or { });
      in
      fx.bind (fx.send "dispatch-policy-includes" { inherit ctx; }) (
        result:
        let
          incs = result.includes or [ ];
          excs = result.excludes or [ ];
          scopeHandlers = aspect.__scopeHandlers or null;
          ctxId = aspect.__ctxId or null;
          emitIncs =
            if incs == [ ] then
              fx.pure [ ]
            else
              builtins.foldl' (
                acc: child:
                fx.bind acc (
                  prev:
                  fx.bind (fx.send "emit-include" (
                    {
                      inherit child;
                      idx = null;
                    }
                    // lib.optionalAttrs (scopeHandlers != null) { __parentScopeHandlers = scopeHandlers; }
                    // lib.optionalAttrs (ctxId != null) { __parentCtxId = ctxId; }
                  )) (r: fx.pure (prev ++ r))
                )
              ) (fx.pure [ ]) incs;
          regExcludes =
            if excs == [ ] then
              fx.pure null
            else
              builtins.foldl' (
                acc: aspectRef:
                fx.bind acc (
                  _:
                  fx.send "register-constraint" {
                    type = "exclude";
                    scope = "subtree";
                    identity = identity.pathKey (identity.aspectPath aspectRef);
                    owner = "policy";
                  }
                )
              ) (fx.pure null) excs;
        in
        fx.bind emitIncs (incResults: fx.bind regExcludes (_: fx.pure incResults))
      );

  emitTransitions =
    aspect:
    let
      # meta.into survives freeform deferredModule; aspect.into is the fallback.
      intoFn = aspect.meta.into or aspect.into or null;
      hasManualInto = intoFn != null && lib.isFunction intoFn;
      # Only fire per-policy dispatch for entity roots (aspects with __entityKind).
      # Inner provides/includes share the entity kind but are not transition points.
      isEntityRoot = aspect ? __entityKind;
      # Fire transition dispatch for any entity root when policies exist.
      # Body guards inside each policy determine applicability per entity kind.
      hasPolicies = isEntityRoot && (den.policies or { }) != { };
    in
    # Dispatch policy include/exclude effects during tree-walk first.
    fx.bind (dispatchPolicyIncludes aspect) (
      policyIncResults:
      let
        doTransition =
          if hasManualInto || hasPolicies then
            fx.send "into-transition" {
              intoFn = if hasManualInto then intoFn else null;
              self = aspect;
            }
          else
            fx.pure [ ];
      in
      fx.bind doTransition (transResults: fx.pure (policyIncResults ++ transResults))
    );

  mkPositionalInclude =
    {
      innerFn,
      ctx,
      name,
      scopeHandlers,
      aspect,
      providerMeta,
    }:
    let
      resolved = innerFn ctx;
      resolvedArgs = if lib.isFunction resolved then lib.functionArgs resolved else { };
    in
    if lib.isFunction resolved && !builtins.isAttrs resolved then
      {
        inherit name;
        meta = providerMeta;
        __fn = resolved;
        __args = resolvedArgs;
      }
      // lib.optionalAttrs (scopeHandlers != null) { __parentScopeHandlers = scopeHandlers; }
      // lib.optionalAttrs (aspect ? __ctxId) { __parentCtxId = aspect.__ctxId; }
    else
      (if builtins.isAttrs resolved then resolved else { })
      // {
        inherit name;
        meta = providerMeta;
        includes = (if builtins.isAttrs resolved then resolved.includes or [ ] else [ ]);
      }
      // lib.optionalAttrs (aspect ? __ctxId) { __ctxId = aspect.__ctxId; };

  mkNamedInclude =
    {
      innerFn,
      providerVal,
      isParamWrapper,
      name,
      scopeHandlers,
      aspect,
      providerMeta,
      providerArgs,
    }:
    {
      inherit name;
      meta =
        providerMeta
        // (
          if isParamWrapper then
            builtins.removeAttrs (providerVal.meta or { }) [
              "provider"
              "selfProvide"
            ]
          else
            { }
        );
      __fn = if lib.isFunction innerFn then innerFn else _: providerVal;
      __args = providerArgs;
    }
    // lib.optionalAttrs (scopeHandlers != null) { __parentScopeHandlers = scopeHandlers; }
    // lib.optionalAttrs (aspect ? __ctxId) { __parentCtxId = aspect.__ctxId; };

  # Emit register-aspect-policy for each entry in aspect.policies.
  # Each policy is stored with ownerIdentity for exclusion rollback.
  emitAspectPolicies =
    aspect:
    let
      policies = aspect.policies or { };
      aspectName = aspect.name or "<anon>";
      nodeIdentity = identity.pathKey (identity.aspectPath aspect);
    in
    if policies == { } then
      fx.pure null
    else
      fx.seq (
        lib.mapAttrsToList (
          policyName: policyFn:
          fx.send "register-aspect-policy" {
            name = "${aspectName}/${policyName}";
            fn = policyFn;
            ownerIdentity = nodeIdentity;
          }
        ) policies
      );

  emitSelfProvide =
    aspect:
    let
      name = aspect.name or "<anon>";
      provides = aspect.provides or { };
      providerVal = provides.${name};
      scopeHandlers = aspect.__scopeHandlers or null;
      ctx = ctxFromHandlers (aspect.__scopeHandlers or { });
      isParamWrapper = isParametricWrapper providerVal;
      innerFn =
        if isParamWrapper then
          providerVal.__fn
        else if builtins.isAttrs providerVal && providerVal ? __fn then
          providerVal.__fn
        else if builtins.isAttrs providerVal && lib.isFunction providerVal then
          providerVal.__functor providerVal
        else
          providerVal;
      providerArgs =
        if isParamWrapper then
          providerVal.__args
        else if lib.isFunction innerFn then
          lib.functionArgs innerFn
        else
          { };
    in
    if provides ? ${name} then
      let
        isPositionalFn = lib.isFunction innerFn && providerArgs == { };
        providerMeta = {
          provider = (aspect.meta.provider or [ ]) ++ [ name ];
          selfProvide = true;
        };
        shared = {
          inherit
            innerFn
            name
            scopeHandlers
            aspect
            providerMeta
            ;
        };
        include =
          if isPositionalFn then
            mkPositionalInclude (shared // { inherit ctx; })
          else
            mkNamedInclude (shared // { inherit providerVal isParamWrapper providerArgs; });
      in
      fx.send "emit-include" include
    else
      fx.pure [ ];

  chainWrap =
    aspect: nodeIdentity: isMeaningful: comp:
    if isMeaningful then
      fx.bind (fx.send "chain-push" {
        identity = nodeIdentity;
      }) (_: fx.bind comp (result: fx.bind (fx.send "chain-pop" null) (_: fx.pure result)))
    else
      comp;

  resolveChildren =
    aspect:
    { isMeaningful, chainIdentity }:
    let
      scopeHandlers = aspect.__scopeHandlers or null;
      ctxId = aspect.__ctxId or null;
      emitCtx = {
        __parentScopeHandlers = scopeHandlers;
        __parentCtxId = ctxId;
      };
      # Includes resolve before transitions so deferred parametric includes
      # drain when context widens during transitions.
      childResolution = fx.bind (emitSelfProvide aspect) (
        selfProvResults:
        fx.bind (emitCrossProvideShims aspect) (
          _:
          fx.bind (emitAspectPolicies aspect) (
            _:
            fx.bind (emitIncludes emitCtx (aspect.includes or [ ])) (
              includeResults:
              fx.bind (emitTransitions aspect) (
                transitionResults: fx.pure (selfProvResults ++ includeResults ++ transitionResults)
              )
            )
          )
        )
      );
    in
    fx.bind (chainWrap aspect chainIdentity isMeaningful childResolution) (
      allChildren:
      let
        resolved = aspect // {
          includes = allChildren;
        };
      in
      fx.bind (fx.send "resolve-complete" resolved) (_: fx.pure resolved)
    );

  # Build a nested sub-aspect from a freeform key and recurse via aspectToEffect.
  emitNestedAspect =
    aspect: k: nodeIdentity:
    let
      rawValue = aspect.${k};
      innerValue =
        if builtins.isAttrs rawValue && rawValue ? __contentValues then
          let
            vals = map (d: d.value) rawValue.__contentValues;
          in
          if builtins.length vals == 1 then builtins.head vals else { imports = vals; }
        else
          rawValue;
      subAspect =
        (if builtins.isAttrs innerValue then innerValue else { })
        // {
          name = k;
          meta = (aspect.meta or { }) // {
            provider = (aspect.meta.provider or [ ]) ++ [ (aspect.name or "<anon>") ];
          };
        }
        // lib.optionalAttrs (aspect ? __scopeHandlers) {
          inherit (aspect) __scopeHandlers;
        }
        // lib.optionalAttrs (aspect ? __ctxId) {
          inherit (aspect) __ctxId;
        };
    in
    aspectToEffect subAspect;

  compileStatic =
    aspect:
    let
      nodeIdentity = identity.pathKey (identity.aspectPath aspect);
      # Chain identity strips ctxId — the chain tracks includes provenance,
      # not fan-out dedup. This keeps chain entries aligned with entry
      # fullNames (provider/name) so parent resolution in graph.nix works.
      chainIdentity = identity.pathKey ((aspect.meta.provider or [ ]) ++ [ (aspect.name or "<anon>") ]);
      rawName = aspect.name or "<anon>";
      isMeaningful = isMeaningfulName rawName;
    in
    fx.bind (fx.effects.hasHandler "class") (
      hasClassHandler:
      fx.bind (if hasClassHandler then fx.send "class" null else fx.pure null) (
        targetClass:
        let
          classified = classifyKeys targetClass aspect;
          inherit (classified)
            classKeys
            traitKeys
            nestedKeys
            unregisteredClassKeys
            ;
          # Unregistered keys enter the dead letter queue for deferred re-classification.
          # targetClass recognition ensures forward-scoped class aliases are not dropped.
          allClassKeys = classKeys;
          ctx = ctxFromHandlers (aspect.__scopeHandlers or { });
          aspectPolicy = aspect.meta.collisionPolicy or null;
          globalPolicy = den.config.classModuleCollisionPolicy or "error";
          deadLetterEffects = map (
            k:
            fx.send "dead-letter" {
              key = k;
              rawValue = aspect.${k};
              aspectIdentity = nodeIdentity;
              aspectName = rawName;
              inherit ctx aspectPolicy globalPolicy;
              parametricResolved = aspect.__parametricResolved or false;
              contextDependent = aspect.meta.contextDependent or false;
            }
          ) unregisteredClassKeys;
        in
        fx.bind (fx.seq (
          [
            (emitClasses aspect allClassKeys nodeIdentity)
            (emitTraits aspect traitKeys nodeIdentity)
            (registerConstraints aspect)
          ]
          ++ map (k: emitNestedAspect aspect k nodeIdentity) nestedKeys
          ++ deadLetterEffects
        )) (_: resolveChildren aspect { inherit isMeaningful chainIdentity; })
      )
    );

  # Submodule functions merge through the type system; bare functions
  # become another parametric level; attrsets merge directly.
  mkParametricNext =
    aspect: base: resolved:
    let
      inherit (den.lib.aspects) isSubmoduleFn;
      isResolvedSubmoduleFn =
        lib.isFunction resolved && !builtins.isAttrs resolved && isSubmoduleFn resolved;
    in
    if lib.isFunction resolved && !builtins.isAttrs resolved then
      if isResolvedSubmoduleFn then
        let
          merged = den.lib.aspects.types.aspectType.merge (aspect.meta.loc or [ (aspect.name or "<anon>") ]) [
            {
              file = aspect.meta.file or "<parametric>";
              value = resolved;
            }
          ];
        in
        base // builtins.removeAttrs merged [ "meta" ]
      else
        base
        // {
          __fn = resolved;
          __args = lib.functionArgs resolved;
        }
    else
      base // builtins.removeAttrs resolved [ "meta" ];

  tagParametricResult =
    aspect: next:
    let
      parentScopeHandlers = aspect.__scopeHandlers or { };
      resolvedScopeHandlers = if builtins.isAttrs next then next.__scopeHandlers or { } else { };
      mergedScopeHandlers = parentScopeHandlers // resolvedScopeHandlers;
    in
    next
    // lib.optionalAttrs (mergedScopeHandlers != { }) { __scopeHandlers = mergedScopeHandlers; }
    // lib.optionalAttrs (aspect ? __ctxId) { inherit (aspect) __ctxId; }
    // {
      __parametricResolved = true;
    };

  maxParametricDepth = 10;

  # Two cases:
  # 1. __args has named args → parametric. Resolve via bind.fn, compile result.
  # 2. Otherwise → static. Strip __fn/__args, compile the attrset directly.
  aspectToEffect =
    aspect:
    let
      userArgs = aspect.__args or { };
      isParametric = userArgs != { };
      depth = aspect.__parametricDepth or 0;
      scopeHandlers = aspect.__scopeHandlers or null;
      scopeFn = if scopeHandlers != null then fx.effects.scope.provide scopeHandlers else null;
    in
    if isParametric then
      if depth >= maxParametricDepth then
        throw "den: parametric resolution exceeded ${toString maxParametricDepth} levels for '${aspect.name or "<anon>"}' — likely a curried function that never bottoms out"
      else
        let
          rawFn = aspect.__fn;
          fn =
            if (aspect.meta.exactMatch or false) && scopeHandlers != null then
              args: rawFn (args // { __scopeKeys = builtins.attrNames scopeHandlers; })
            else
              rawFn;
          resolveFn = if scopeFn != null then scopeFn (fx.bind.fn userArgs fn) else fx.bind.fn userArgs fn;
        in
        fx.bind resolveFn (
          resolved:
          let
            base = {
              inherit (aspect) name;
              meta =
                (aspect.meta or { })
                // (if builtins.isAttrs resolved then resolved.meta or { } else { })
                // {
                  isParametric = true;
                  fnArgNames = builtins.attrNames userArgs;
                };
            }
            // lib.optionalAttrs (aspect ? into) { inherit (aspect) into; }
            // lib.optionalAttrs (aspect ? provides) { inherit (aspect) provides; };
            next = mkParametricNext aspect base resolved;
            tagged = tagParametricResult aspect next // {
              __parametricDepth = depth + 1;
            };
          in
          aspectToEffect tagged
        )
    else
      compileStatic (
        builtins.removeAttrs aspect [
          "__fn"
          "__args"
          "__parametricDepth"
        ]
      );

in
{
  inherit
    aspectToEffect
    drainDeadLettersHandler
    emitIncludes
    emitTransitions
    emitSelfProvide
    structuralKeysSet
    wrapClassModule
    ctxFromHandlers
    ;
}
