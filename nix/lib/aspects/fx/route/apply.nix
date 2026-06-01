# Apply registered routes — fold over deduped route specs,
# dispatching complex (forward-derived) vs simple (path nesting).
{
  lib,
  den,
  wrapRouteModules,
  collectClassMods,
}:
let
  # Root-scope `fromClass` content a child-scope forward may pull in. When
  # `fromClass` is a class some entity in the chain owns, root content under it
  # is that entity's own declaration, not aggregation fodder — restrict to
  # shared `den.default` (host class content reaches users opt-in via
  # host-aspects). A custom forward-only class (e.g. `atuin`) only exists to
  # feed forwards, so its root content is a legitimate source; keep it in full.
  filterRootModules =
    scopeContexts: spec: rootModules: isDenDefaultModule:
    let
      childCtx = scopeContexts.${spec.sourceScopeId} or { };
      # Classes owned by each entity kind in the chain. Total over kinds so the
      # filter never falls open for a non-user-owned scope (host, standalone home).
      ownedClasses =
        (childCtx.user.classes or [ ])
        ++ lib.optional (childCtx ? host) childCtx.host.class
        ++ lib.optional (childCtx ? home) childCtx.home.class;
    in
    if builtins.elem spec.fromClass ownedClasses then
      builtins.filter isDenDefaultModule rootModules
    else
      rootModules;

  getCollectedSource =
    acc: spec: rootScopeId: isDenDefaultModule: scopeContexts:
    let
      sid = spec.sourceScopeId;
    in
    if rootScopeId != null && sid != rootScopeId then
      let
        ownModules = (acc.perScope.${sid} or { }).${spec.fromClass} or [ ];
        rootModules = (acc.perScope.${rootScopeId} or { }).${spec.fromClass} or [ ];
      in
      filterRootModules scopeContexts spec rootModules isDenDefaultModule ++ ownModules
    else
      acc.classImports.${spec.fromClass} or [ ];

  resolveSourceFallback =
    spec: fxResolve: scopeContexts: ctx:
    if !(spec ? sourceAspect) || fxResolve == null then
      [ ]
    else
      let
        normalized = den.lib.aspects.normalizeRoot spec.sourceAspect;
        sourceCtx = scopeContexts.${spec.sourceScopeId} or ctx;
      in
      (fxResolve {
        class = spec.fromClass;
        self = normalized;
        ctx =
          sourceCtx // den.lib.aspects.fx.aspect.ctxFromHandlers (spec.sourceAspect.__scopeHandlers or { });
      }).imports;

  appendToClass = acc: cls: sid: newMods: {
    classImports = acc.classImports // {
      ${cls} = (acc.classImports.${cls} or [ ]) ++ newMods;
    };
    perScope = acc.perScope // {
      ${sid} = (acc.perScope.${sid} or { }) // {
        ${cls} = ((acc.perScope.${sid} or { }).${cls} or [ ]) ++ newMods;
      };
    };
  };

  applyComplexRoute =
    acc:
    {
      route,
      rootScopeId,
      scopeContexts,
      ctx,
      fxResolve,
      buildForwardAspect,
      isDenDefaultModule,
    }:
    let
      spec = route;
      collected = getCollectedSource acc spec rootScopeId isDenDefaultModule scopeContexts;
      sourceModules =
        if collected != [ ] then collected else resolveSourceFallback spec fxResolve scopeContexts ctx;
      sourceModule = spec.mapModule { imports = sourceModules; };
      newMods = collectClassMods spec.intoClass (buildForwardAspect spec sourceModule);
    in
    appendToClass acc spec.intoClass spec.sourceScopeId newMods;

  mkAdapterFunctor =
    route: sourceModules:
    let
      adapterMod = route.adapterModule or null;
      sourceModule = {
        imports = sourceModules;
      };
      guardFn = route.guard or (_: lib.id);
      adaptArgsFn = route.adaptArgs or (_: { });
      intoPathFn = route.intoPathFn or (_: route.path);
      key = route.adapterKey;
      guardArgs = route.guardArgs or { };
      intoPathArgs = route.intoPathArgs or { };
      adaptArgv = route.adaptArgv or { };
      freeformMod =
        route.freeformMod or {
          config._module.freeformType = lib.types.lazyAttrsOf lib.types.unspecified;
        };
      adapterMods =
        if adapterMod != null then
          [
            freeformMod
            adapterMod
          ]
        else
          [ freeformMod ];
    in
    {
      __functionArgs = guardArgs // intoPathArgs // adaptArgv;
      __functor = _: args: {
        options.den.fwd.${key} = lib.mkOption {
          defaultText = lib.literalExpression "{ }";
          default = { };
          type = lib.types.submoduleWith {
            specialArgs = adaptArgsFn args;
            modules = adapterMods ++ [ sourceModule ];
          };
        };
        config = guardFn args (lib.setAttrByPath (intoPathFn args) args.config.den.fwd.${key});
      };
    };

  # Collect class modules from a scope and all its descendants.
  collectFromSubtree =
    wrappedPerScope: scopeParent: rootScopeId: fromClass:
    let
      allScopeIds = builtins.attrNames wrappedPerScope;
      isInSubtree =
        sid:
        sid == rootScopeId
        || (
          let
            parent = scopeParent.${sid} or null;
          in
          parent != null && parent != sid && isInSubtree parent
        );
      subtreeScopes = builtins.filter isInSubtree allScopeIds;
    in
    lib.concatMap (sid: wrappedPerScope.${sid}.${fromClass} or [ ]) subtreeScopes;

  applySimpleRoute =
    acc:
    {
      route,
      wrappedPerScope,
      scopeParent,
    }:
    let
      isFlakeRoute = route.intoClass == "flake";
      # Subtree collection only for flake routes — parametric class keys
      # resolve at entity scopes (host/user) which are descendants of the
      # route's scope.  Non-flake routes (e.g. into "flake-parts") collect
      # only from their own scope to avoid pulling modules from unrelated
      # entity subtrees whose scope args won't be available after adaptArgs.
      sourceModules =
        if isFlakeRoute || (route.collectSubtree or false) then
          collectFromSubtree wrappedPerScope scopeParent route.sourceScopeId route.fromClass
        else
          let
            scopeExists = wrappedPerScope ? ${route.sourceScopeId};
          in
          if !scopeExists then [ ] else wrappedPerScope.${route.sourceScopeId}.${route.fromClass} or [ ];
      hasInstantiate = route.instantiate or null != null;
      adapterMod = route.adapterModule or null;
      modulesWithAdapter = if adapterMod == null then sourceModules else sourceModules ++ [ adapterMod ];
      ensureEntry =
        lib.optional
          (
            !isFlakeRoute
            && route.adaptArgs or null != null
            && route.path or [ ] != [ ]
            && modulesWithAdapter == [ ]
          )
          {
            config = lib.setAttrByPath route.path { };
          };
      isAdapterRoute = route.adapterKey or null != null;
      adapterWrapped = lib.optional isAdapterRoute (mkAdapterFunctor route sourceModules);
      # Route with instantiate: collect modules, call instantiate function,
      # place the result (a derivation) at the target path.
      instantiateWrapped =
        let
          adaptArgsFn = route.adaptArgs or (_: { });
          extraArgs = adaptArgsFn { };
          evaluated = route.instantiate ({ modules = sourceModules; } // extraArgs);
        in
        [
          {
            config = lib.setAttrByPath route.path evaluated;
          }
        ];
      wrappedModules =
        if hasInstantiate then
          if sourceModules == [ ] then [ ] else instantiateWrapped
        else if modulesWithAdapter == [ ] then
          ensureEntry
        else if isAdapterRoute then
          adapterWrapped
        else
          wrapRouteModules {
            modules = modulesWithAdapter;
            inherit (route) path;
            guard = route.guard or null;
            adaptArgs = route.adaptArgs or null;
          };
    in
    appendToClass acc route.intoClass route.sourceScopeId wrappedModules;

  isDenDefaultModule = mod: lib.hasSuffix "@default" (mod.key or mod._file or "");

  # Collect adapterKeys that exist at child (non-root) scopes.
  findChildScopeKeys =
    rootScopeId: rawRoutes:
    builtins.foldl' (
      acc: r:
      let
        ak = r.adapterKey or null;
      in
      if ak != null && rootScopeId != null && r.sourceScopeId != rootScopeId then
        acc // { ${ak} = true; }
      else
        acc
    ) { } rawRoutes;

  # Dedup routes: suppress root-scope when child-scope handles the same forward,
  # and dedup same adapterKey@scope.
  dedupRoutes =
    rootScopeId: rawRoutes:
    let
      childScopeKeys = findChildScopeKeys rootScopeId rawRoutes;
      go =
        seen: routes:
        if routes == [ ] then
          [ ]
        else
          let
            r = builtins.head routes;
            rest = builtins.tail routes;
            ak = r.adapterKey or null;
            isRedundantRoot =
              ak != null && rootScopeId != null && r.sourceScopeId == rootScopeId && childScopeKeys ? ${ak};
            key = if ak != null then "${ak}@${r.sourceScopeId}" else null;
          in
          if isRedundantRoot then
            go seen rest
          else if key != null && seen ? ${key} then
            go seen rest
          else
            [ r ] ++ go (if key != null then seen // { ${key} = true; } else seen) rest;
    in
    go { } rawRoutes;

  # Topologically sort routes: when forward A's intoClass feeds forward
  # B's fromClass at the same scope, A must fire before B.  Only
  # reorders __complexForward routes; non-forward routes keep their
  # original position relative to other non-forwards.  (#567)
  topoSortRoutes =
    routes:
    let
      indexed = lib.imap0 (i: r: { inherit i r; }) routes;
      # Build producer map: intoClass@scope → [route indices]
      producerMap = builtins.foldl' (
        acc:
        { i, r }:
        if r.__complexForward or false then
          let
            key = "${r.intoClass}@${r.sourceScopeId}";
          in
          acc // { ${key} = (acc.${key} or [ ]) ++ [ i ]; }
        else
          acc
      ) { } indexed;
      # A complex forward is "depends on producers" when its fromClass@scope
      # has entries in producerMap (meaning another forward produces into it).
      hasDeps =
        { i, r }: (r.__complexForward or false) && producerMap ? "${r.fromClass}@${r.sourceScopeId}";
      # Partition: routes without deps first, routes with deps last.
      # This is a single-level toposort (sufficient for A→B chains).
      noDeps = builtins.filter (ir: !hasDeps ir) indexed;
      withDeps = builtins.filter hasDeps indexed;
    in
    map (ir: ir.r) (noDeps ++ withDeps);

  # Main entry: dedup routes, fold applying each.
  applyRoutes =
    {
      scopedRoutes,
      wrappedPerScope,
      classImports,
      scopeParent ? { },
      scopeContexts ? { },
      ctx ? { },
      fxResolve ? null,
      rootScopeId ? null,
      buildForwardAspect ? null,
    }:
    let
      allRoutes = topoSortRoutes (
        dedupRoutes rootScopeId (lib.concatLists (lib.attrValues scopedRoutes))
      );
    in
    builtins.foldl'
      (
        acc: route:
        if route.__complexForward or false then
          applyComplexRoute acc {
            inherit
              route
              rootScopeId
              scopeContexts
              ctx
              fxResolve
              buildForwardAspect
              isDenDefaultModule
              ;
          }
        else
          applySimpleRoute acc { inherit route wrappedPerScope scopeParent; }
      )
      {
        inherit classImports;
        perScope = wrappedPerScope;
      }
      allRoutes;
in
{
  inherit applyRoutes;
}
