{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  identity = den.lib.aspects.fx.identity;
  inherit (den.lib.aspects.fx.handlers) constantHandler emitCrossProvideShims;
  inherit (den.lib.aspects) isMeaningfulName;
  inherit (den.lib.synthesizePolicies) resolveArgsSatisfied;
  inherit (den.lib.policyTypes) policyFnArgs;
  inherit (den.lib.aspects.fx.pipeline) mkScopeId;

  # Context identity string — used for ctx-seen dedup keys.
  mkCtxId =
    ctx:
    lib.concatStringsSep "," (
      lib.sort (a: b: a < b) (
        map (
          attrName:
          let
            attrVal = ctx.${attrName};
          in
          if builtins.isAttrs attrVal && attrVal ? name then
            attrVal.name
          else if builtins.isString attrVal then
            attrVal
          else if builtins.isInt attrVal || builtins.isFloat attrVal then
            toString attrVal
          else
            attrName
        ) (builtins.attrNames ctx)
      )
    );

  # Schema entity kinds — used to classify resolve effects.
  policySchemaKinds = builtins.filter (
    n: n != "conf" && !(lib.hasPrefix "_" n) && (den.schema.${n}.isEntity or false)
  ) (builtins.attrNames (den.schema or { }));

  inherit (import ./key-classification.nix { inherit lib den; }) structuralKeysSet classifyKeys;

  inherit (import ./class-module.nix { inherit lib den; }) wrapClassModule;

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

  inherit (import ./include-emit.nix { inherit lib den; } { inherit ctxFromHandlers; })
    emitIncludes
    emitSelfProvide
    emitAspectPolicies
    registerConstraints
    ;

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
              __rawEntry = true;
              isContextDependent =
                (aspect.__parametricResolved or false) || (aspect.meta.contextDependent or false);
            })
          ]
        ) indexed
      ) classKeys
    );

  # Classify a resolve effect into schema vs enrichment.
  classifyResolve =
    e:
    let
      keys = builtins.attrNames e.value;
      schemaKeys = builtins.filter (k: builtins.elem k policySchemaKinds) keys;
      enrichKeys = builtins.filter (k: !builtins.elem k policySchemaKinds) keys;
      hasTarget = e.__targetKind or null != null;
    in
    if hasTarget then
      {
        schema = e;
        enrichment = null;
      }
    else if schemaKeys == [ ] then
      {
        schema = null;
        enrichment = e.value;
      }
    else if enrichKeys == [ ] then
      {
        schema = e;
        enrichment = null;
      }
    else
      {
        schema = e // {
          value = lib.filterAttrs (k: _: builtins.elem k policySchemaKinds) e.value;
        };
        enrichment = lib.filterAttrs (k: _: !builtins.elem k policySchemaKinds) e.value;
      };

  maxPolicyIterations = 10;

  # Inline policy dispatch for entity roots.  Replaces the old
  # handler — reads state via fx.effects.state.get
  # and uses scope.provide for context expansion during schema resolves.
  installPolicies =
    aspect:
    let
      entityKind = aspect.__entityKind;
      ctx = ctxFromHandlers (aspect.__scopeHandlers or { });
    in
    fx.bind fx.effects.state.get (
      state:
      let
        scope = state.currentScope;
        currentCtx = if scope == null then ctx else (state.scopeContexts null).${scope} or ctx;

        # Dedup: skip if this entityKind@scope was already dispatched.
        # Multiple aspects in the tree can have __entityKind, but policies
        # should only fire once per entity kind per scope.
        dispatchKey = "${entityKind}@${scope}";
        alreadyDispatched = builtins.elem dispatchKey ((state.dispatchedPolicies or (_: [ ])) null);

        # Three policy sources.
        globalPolicies = den.policies or { };
        schemaPolicies = (den.schema.${entityKind} or { }).policies or { };
        allDirectPolicies = globalPolicies // schemaPolicies;

        # Flatten aspect policies from all scopes.
        aspectPolicies = builtins.foldl' (acc: v: acc // v) { } (
          builtins.attrValues ((state.scopedAspectPolicies or (_: { })) null)
        );

        # Dispatch all direct (global + schema) policies against a context.
        dispatchDirect =
          firedPolicies: resolveCtx:
          lib.concatLists (
            lib.mapAttrsToList (
              name: policy:
              let
                argsOk = resolveArgsSatisfied policy resolveCtx;
              in
              if !argsOk || builtins.elem name firedPolicies then
                [ ]
              else
                let
                  rawEffects =
                    let
                      result = policy resolveCtx;
                    in
                    if builtins.isList result then result else [ result ];
                in
                if rawEffects == [ ] then
                  [ ]
                else
                  [
                    {
                      policyName = name;
                      effects = rawEffects;
                    }
                  ]
            ) allDirectPolicies
          );

        # Dispatch aspect policies against a context.
        dispatchAspect =
          firedPolicies: resolveCtx:
          let
            entries = lib.attrsToList aspectPolicies;
            matching = builtins.filter (
              e:
              let
                fargs = policyFnArgs e.value.fn;
                requiredArgs = builtins.filter (k: !fargs.${k}) (builtins.attrNames fargs);
              in
              builtins.all (k: resolveCtx ? ${k}) requiredArgs && !builtins.elem e.name firedPolicies
            ) entries;
          in
          map (
            entry:
            let
              rawEffects =
                let
                  result = entry.value.fn resolveCtx;
                in
                if builtins.isList result then result else [ result ];
            in
            {
              policyName = entry.name;
              effects = rawEffects;
            }
          ) matching;

        # Combined dispatch returning classified results.
        mkDispatch =
          firedPolicies: resolveCtx:
          let
            allResults = dispatchDirect firedPolicies resolveCtx ++ dispatchAspect firedPolicies resolveCtx;

            # Classify effects per policy result.
            classified = map (
              r:
              let
                resolveEffects = builtins.filter (
                  e: builtins.isAttrs e && (e.__policyEffect or "") == "resolve" && e.value != { }
                ) r.effects;
                includeEffects = builtins.filter (
                  e: builtins.isAttrs e && (e.__policyEffect or "") == "include"
                ) r.effects;
                excludeEffects = builtins.filter (
                  e: builtins.isAttrs e && (e.__policyEffect or "") == "exclude"
                ) r.effects;
                routeEffects = builtins.filter (
                  e: builtins.isAttrs e && (e.__policyEffect or "") == "route"
                ) r.effects;
                instantiateEffects = builtins.filter (
                  e: builtins.isAttrs e && (e.__policyEffect or "") == "instantiate"
                ) r.effects;

                resolveClassified = map classifyResolve resolveEffects;
                schemaEffects = builtins.filter (c: c.schema != null) resolveClassified;
                enrichEffects = builtins.filter (c: c.enrichment != null) resolveClassified;
                mergedEnrichment = builtins.foldl' (acc: c: acc // c.enrichment) { } enrichEffects;
              in
              {
                inherit (r) policyName;
                inherit
                  schemaEffects
                  mergedEnrichment
                  includeEffects
                  excludeEffects
                  routeEffects
                  instantiateEffects
                  ;
              }
            ) allResults;

            allEnrichment = builtins.foldl' (acc: r: acc // r.mergedEnrichment) { } classified;
            # Per-policy include pairing for cross-provider patterns.
            # Prevents double-fire via drain-deferred when a resolve.to policy
            # also has includes — includes travel with their schema effects.
            paired = map (
              r:
              let
                isCrossProvider =
                  r.schemaEffects != [ ]
                  && r.includeEffects != [ ]
                  && builtins.any (se: se.schema.__targetKind or null != null) r.schemaEffects;
              in
              r // { inherit isCrossProvider; }
            ) classified;
            allSchemaEffects = builtins.concatMap (
              r:
              if r.isCrossProvider then
                map (se: se // { __policyIncludes = map (e: e.value) r.includeEffects; }) r.schemaEffects
              else
                r.schemaEffects
            ) paired;
            allIncludeEffects = builtins.concatMap (
              r: if r.isCrossProvider then [ ] else r.includeEffects
            ) paired;
            allExcludeEffects = builtins.concatMap (r: r.excludeEffects) classified;
            allRouteEffects = builtins.concatMap (
              r: map (re: re // { __routePolicyName = r.policyName; }) r.routeEffects
            ) classified;
            allInstantiateEffects = builtins.concatMap (
              r: map (ie: ie // { __instantiatePolicyName = r.policyName; }) r.instantiateEffects
            ) classified;
            # Track which policies fired (had any effects).
            firedNames = map (r: r.policyName) (
              builtins.filter (
                r:
                r.schemaEffects != [ ]
                || r.mergedEnrichment != { }
                || r.includeEffects != [ ]
                || r.excludeEffects != [ ]
                || r.routeEffects != [ ]
                || r.instantiateEffects != [ ]
              ) classified
            );
          in
          {
            enrichment = allEnrichment;
            schemaEffects = allSchemaEffects;
            includeEffects = allIncludeEffects;
            excludeEffects = allExcludeEffects;
            routeEffects = allRouteEffects;
            instantiateEffects = allInstantiateEffects;
            inherit firedNames;
          };

        # Process include/exclude effects via existing handlers, collecting results.
        policyEmitIncludes =
          effects:
          builtins.foldl' (
            acc: e:
            fx.bind acc (
              prev:
              fx.bind (fx.send "emit-include" {
                child = e.value;
                idx = null;
              }) (r: fx.pure (prev ++ r))
            )
          ) (fx.pure [ ]) effects;

        policyEmitExcludes =
          effects:
          builtins.foldl' (
            acc: e:
            fx.bind acc (
              _:
              fx.send "register-constraint" {
                type = "exclude";
                scope = "subtree";
                identity = identity.pathKey (identity.aspectPath e.value);
                owner = "policy";
              }
            )
          ) (fx.pure null) effects;

        policyEmitRoutes =
          effects:
          builtins.foldl' (acc: e: fx.bind acc (_: fx.send "register-route" e.value)) (fx.pure null) effects;

        policyEmitInstantiates =
          effects:
          builtins.foldl' (
            acc: e: fx.bind acc (_: fx.send "register-instantiate" e.value)
          ) (fx.pure null) effects;

        # Process schema resolve effects: ctx-seen dedup, push scope, walk entity, pop scope.
        # includeAspects: standalone includes from policies (backward compat, go to all entities).
        # Each schema effect also carries per-resolve includes via __includes.
        processSchemaResolves =
          includeAspects: schemaEffects: enrichedCtx:
          let
            isFanOut = builtins.length schemaEffects > 1;
          in
          builtins.foldl' (
            acc: schemaEffect:
            fx.bind acc (
              prevResults:
              let
                # Determine target entity kind from the schema effect.
                keys = builtins.attrNames schemaEffect.schema.value;
                targetKind =
                  if schemaEffect.schema.__targetKind or null != null then
                    schemaEffect.schema.__targetKind
                  else
                    lib.findFirst (k: builtins.elem k policySchemaKinds) (
                      if keys != [ ] then builtins.head keys else entityKind
                    ) keys;
                # Build context for this schema resolve.
                resolveBindings = schemaEffect.schema.value;
                scopedCtx = enrichedCtx // resolveBindings;
                ctxNames = mkCtxId scopedCtx;
                ctxKey = if isFanOut then "${targetKind}/{${ctxNames}}" else targetKind;
                newScopeId = mkScopeId scopedCtx;
                # Override the class handler for child entities. The pipeline's
                # root class (e.g. "nixos") is wrong for child entity scopes —
                # class-generic aspects like unfree use { class, ... }: to emit
                # to the current class. At user scope, class should be the
                # user's primary class (e.g. "homeManager").
                entityClass =
                  let
                    entity = resolveBindings.${targetKind} or null;
                    classes = if entity != null then entity.classes or null else null;
                  in
                  if classes != null && classes != [ ] then builtins.head classes else null;
                scopeHandlersForCtx = constantHandler (
                  scopedCtx // lib.optionalAttrs (entityClass != null) { class = entityClass; }
                );

                # Set scope — save parentScope, set currentScope to child.
                setScope = fx.effects.state.modify (
                  st:
                  let
                    parentScope = st.currentScope;
                    isSameScope = newScopeId == parentScope;
                  in
                  st
                  // {
                    currentScope = newScopeId;
                    scopeContexts = _: (st.scopeContexts null) // { ${newScopeId} = scopedCtx; };
                    scopeParent =
                      _: (st.scopeParent null) // lib.optionalAttrs (!isSameScope) { ${newScopeId} = parentScope; };
                    scopedAspectPolicies =
                      _:
                      let
                        all = st.scopedAspectPolicies null;
                        parentPolicies = all.${parentScope} or { };
                      in
                      all // { ${newScopeId} = (all.${newScopeId} or { }) // parentPolicies; };
                  }
                );

                # Restore scope — set currentScope back to parent.
                restoreScope = fx.effects.state.modify (
                  st:
                  st
                  // {
                    currentScope = scope;
                  }
                );

                # Full entity resolution: push scope, resolve entity, walk tree,
                # drain deferred, pop scope.  Wrapped in scope.provide so context
                # handlers are visible to the tree walk.
                # Per-policy includes: includes from the same policy as this resolve.
                policyIncludes = schemaEffect.__policyIncludes or [ ];
                # Per-resolve includes from policy.resolve { __includes = [...]; }
                resolveIncludes = schemaEffect.schema.includes or [ ];

                fullResolution = fx.bind setScope (
                  _:
                  fx.effects.scope.provide scopeHandlersForCtx (
                    fx.bind (fx.send "resolve-entity" { kind = targetKind; }) (
                      rawEntity:
                      let
                        entity = rawEntity // {
                          includes = (rawEntity.includes or [ ]) ++ includeAspects ++ policyIncludes ++ resolveIncludes;
                        };
                      in
                      fx.bind (aspectToEffect entity) (
                        childResult:
                        fx.bind (fx.send "drain-deferred" scopedCtx) (
                          satisfiable:
                          fx.bind
                            (builtins.foldl' (
                              acc': deferred:
                              fx.bind acc' (
                                prev:
                                let
                                  deferredTagged = deferred.child // {
                                    __scopeHandlers = scopeHandlersForCtx;
                                    __ctxId = ctxNames;
                                  };
                                in
                                fx.bind (aspectToEffect deferredTagged) (resolved: fx.pure (prev ++ [ resolved ]))
                              )
                            ) (fx.pure (prevResults ++ [ childResult ])) satisfiable)
                            (
                              allResults:
                              # Propagate root-scope forward specs to this child scope.
                              # Root forwards are templates from den.default; each child
                              # scope that has emissions for the forward's source class
                              # gets its own copy for per-scope isolated execution.
                              fx.bind (fx.effects.state.get) (
                                postWalkState:
                                let
                                  rootSid = postWalkState.rootScopeId;
                                  rootForwards = (postWalkState.scopedForwardSpecs null).${rootSid} or [ ];
                                  childClasses = (postWalkState.scopedClassImports null).${newScopeId} or { };
                                  relevantForwards = builtins.filter (fwd: childClasses ? ${fwd.fromClass}) rootForwards;
                                  childForwards = map (fwd: fwd // { sourceScopeId = newScopeId; }) relevantForwards;
                                in
                                if childForwards == [ ] then
                                  fx.bind restoreScope (_: fx.pure allResults)
                                else
                                  fx.bind (fx.effects.state.modify (
                                    st:
                                    st
                                    // {
                                      scopedForwardSpecs =
                                        _:
                                        let
                                          all = st.scopedForwardSpecs null;
                                        in
                                        all
                                        // {
                                          ${newScopeId} = (all.${newScopeId} or [ ]) ++ childForwards;
                                        };
                                    }
                                  )) (_: fx.bind restoreScope (_: fx.pure allResults))
                              )
                            )
                        )
                      )
                    )
                  )
                );

                # Supplemental: emit only new aspects as includes (entity already resolved).
                supplementalResolution =
                  newAspectValues:
                  builtins.foldl' (
                    sAcc: supAspect:
                    fx.bind sAcc (
                      sPrev:
                      fx.bind (fx.send "emit-include" {
                        child = supAspect;
                        idx = null;
                        __parentScopeHandlers = scopeHandlersForCtx;
                        __parentCtxId = ctxNames;
                      }) (_: fx.pure sPrev)
                    )
                  ) (fx.pure prevResults) newAspectValues;

                policyAspectPaths = map (a: identity.pathKey (identity.aspectPath a)) (
                  includeAspects ++ policyIncludes ++ resolveIncludes
                );
              in
              # ctx-seen dedup: skip re-resolution of same entity context.
              fx.bind
                (fx.send "ctx-seen" {
                  key = ctxKey;
                  aspects = policyAspectPaths;
                  aspectValues = includeAspects;
                })
                (
                  { isFirst, newAspectValues }:
                  if isFirst then
                    fullResolution
                  else if newAspectValues != [ ] then
                    supplementalResolution newAspectValues
                  else
                    fx.pure prevResults
                )
            )
          ) (fx.pure [ ]) schemaEffects;

        # Fixed-point iteration: dispatch, collect enrichment, re-dispatch on widen.
        emptyAcc = {
          schemaEffects = [ ];
          includeEffects = [ ];
          excludeEffects = [ ];
          routeEffects = [ ];
          instantiateEffects = [ ];
        };

        iterate =
          iteration: accEnrichment: accEffects: firedPolicies: currentResolveCtx:
          let
            dispatched = mkDispatch firedPolicies currentResolveCtx;
            newFiredNames = builtins.filter (n: !builtins.elem n firedPolicies) dispatched.firedNames;
            updatedFired = firedPolicies ++ newFiredNames;
            newEnrichKeys = builtins.filter (k: !accEnrichment ? ${k}) (
              builtins.attrNames dispatched.enrichment
            );
            combinedEffects = {
              schemaEffects = accEffects.schemaEffects ++ dispatched.schemaEffects;
              includeEffects = accEffects.includeEffects ++ dispatched.includeEffects;
              excludeEffects = accEffects.excludeEffects ++ dispatched.excludeEffects;
              routeEffects = accEffects.routeEffects ++ dispatched.routeEffects;
              instantiateEffects = accEffects.instantiateEffects ++ dispatched.instantiateEffects;
            };
          in
          if newEnrichKeys == [ ] then
            let
              enrichedCtx = currentCtx // accEnrichment // dispatched.enrichment;
              # Standalone includes (not carried by any resolve) still go to
              # entity walks for backward compatibility.  Per-resolve __includes
              # are added per-entity inside processSchemaResolves.
              includeAspects = map (e: e.value) combinedEffects.includeEffects;
              hasSchemaResolves = combinedEffects.schemaEffects != [ ];
            in
            fx.bind (policyEmitExcludes combinedEffects.excludeEffects) (
              _:
              fx.bind (policyEmitRoutes combinedEffects.routeEffects) (
                _:
                fx.bind (policyEmitInstantiates combinedEffects.instantiateEffects) (
                  _:
                  if hasSchemaResolves then
                    processSchemaResolves includeAspects combinedEffects.schemaEffects enrichedCtx
                  else
                    policyEmitIncludes combinedEffects.includeEffects
                )
              )
            )
          else if iteration >= maxPolicyIterations then
            throw "den: installPolicies enrichment iteration exceeded ${toString maxPolicyIterations} — likely a cycle (${entityKind})"
          else
            let
              combinedEnrichment = accEnrichment // dispatched.enrichment;
              enrichedCtx = currentCtx // combinedEnrichment;
              enrichHandlers = constantHandler combinedEnrichment;
              nextResolveCtx = enrichedCtx // {
                __entityKind = entityKind;
              };
            in
            fx.bind
              (fx.effects.state.modify (
                st:
                st
                // {
                  scopeContexts = _: (st.scopeContexts null) // { ${st.currentScope} = enrichedCtx; };
                }
              ))
              (
                _:
                fx.bind (fx.effects.scope.provide enrichHandlers (
                  fx.bind (fx.send "drain-deferred" enrichedCtx) (
                    satisfiable:
                    builtins.foldl' (
                      acc: deferred:
                      fx.bind acc (
                        _:
                        let
                          deferScopeHandlers = constantHandler enrichedCtx;
                          deferredTagged = deferred.child // {
                            __scopeHandlers = deferScopeHandlers;
                          };
                        in
                        fx.bind (aspectToEffect deferredTagged) (_: fx.pure null)
                      )
                    ) (fx.pure null) satisfiable
                  )
                )) (_: iterate (iteration + 1) combinedEnrichment combinedEffects updatedFired nextResolveCtx)
              );

        resolveCtx = currentCtx // {
          __entityKind = entityKind;
        };
      in
      if alreadyDispatched then
        fx.pure [ ]
      else
        fx.bind (fx.effects.state.modify (
          st:
          st
          // {
            dispatchedPolicies = _: ((st.dispatchedPolicies or (_: [ ])) null) ++ [ dispatchKey ];
          }
        )) (_: iterate 0 { } emptyAcc [ ] resolveCtx)
    );

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
      # Includes resolve before policy dispatch so deferred parametric
      # includes drain when context widens during entity resolution.
      childResolution = fx.bind (emitSelfProvide aspect) (
        selfProvResults:
        fx.bind (emitCrossProvideShims aspect) (
          _:
          fx.bind (emitAspectPolicies aspect) (
            _:
            fx.bind (emitIncludes emitCtx (aspect.includes or [ ])) (
              includeResults:
              if !(aspect ? __entityKind) then
                fx.pure (selfProvResults ++ includeResults)
              else
                fx.bind (installPolicies aspect) (
                  policyResults: fx.pure (selfProvResults ++ includeResults ++ policyResults)
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
            nestedKeys
            unregisteredClassKeys
            ;
          allClassKeys = classKeys ++ unregisteredClassKeys;
        in
        fx.bind (fx.seq (
          [
            (emitClasses aspect allClassKeys nodeIdentity)
            (registerConstraints aspect)
          ]
          ++ map (k: emitNestedAspect aspect k nodeIdentity) nestedKeys
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
    emitIncludes
    emitSelfProvide
    structuralKeysSet
    wrapClassModule
    ctxFromHandlers
    ;
}
