# Apply registered routes — fold over deduped route specs,
# dispatching complex (forward-derived) vs simple (path nesting).
{
  lib,
  den,
  wrapRouteModules,
  collectClassMods,
}:
let
  # Apply a complex forward-derived route (Tier 2 with submodule eval).
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
      sid = spec.sourceScopeId;
      sourceModules =
        if rootScopeId != null && sid != rootScopeId then
          let
            ownModules = (acc.perScope.${sid} or { }).${spec.fromClass} or [ ];
            rootModules = (acc.perScope.${rootScopeId} or { }).${spec.fromClass} or [ ];
            sharedModules = builtins.filter isDenDefaultModule rootModules;
          in
          sharedModules ++ ownModules
        else
          acc.classImports.${spec.fromClass} or [ ];
      resolvedSourceModules =
        if sourceModules != [ ] then
          sourceModules
        else if spec ? sourceAspect && fxResolve != null then
          let
            normalized = den.lib.aspects.normalizeRoot spec.sourceAspect;
            sourceCtx = scopeContexts.${sid} or ctx;
            sourceResult = fxResolve {
              class = spec.fromClass;
              self = normalized;
              ctx =
                sourceCtx // den.lib.aspects.fx.aspect.ctxFromHandlers (spec.sourceAspect.__scopeHandlers or { });
            };
          in
          sourceResult.imports
        else
          [ ];
      sourceModule = spec.mapModule { imports = resolvedSourceModules; };
      forwardAspect = buildForwardAspect spec sourceModule;
      newMods = collectClassMods spec.intoClass forwardAspect;
    in
    {
      classImports = acc.classImports // {
        ${spec.intoClass} = (acc.classImports.${spec.intoClass} or [ ]) ++ newMods;
      };
      perScope = acc.perScope // {
        ${sid} = (acc.perScope.${sid} or { }) // {
          ${spec.intoClass} = ((acc.perScope.${sid} or { }).${spec.intoClass} or [ ]) ++ newMods;
        };
      };
    };

  # Apply a simple route (Tier 1 path nesting or Tier 2 adapter).
  applySimpleRoute =
    acc:
    {
      route,
      wrappedPerScope,
    }:
    let
      scopeExists = wrappedPerScope ? ${route.sourceScopeId};
      sourceModules =
        if !scopeExists then
          builtins.trace
            "den: route from '${route.fromClass}' — source scope '${route.sourceScopeId}' not found in pipeline (cross-pipeline routing requires fleet scope)"
            [ ]
        else
          wrappedPerScope.${route.sourceScopeId}.${route.fromClass} or [ ];
      adapterMod = route.adapterModule or null;
      modulesWithAdapter = if adapterMod == null then sourceModules else sourceModules ++ [ adapterMod ];
      isFlakeRoute = route.intoClass == "flake";
      ensureEntry =
        if
          !isFlakeRoute
          && route.adaptArgs or null != null
          && route.path or [ ] != [ ]
          && modulesWithAdapter == [ ]
        then
          [
            (_: {
              config = lib.setAttrByPath route.path (_: { imports = [ ]; });
            })
          ]
        else
          [ ];
      isAdapterRoute = route.adapterKey or null != null;
      adapterWrapped =
        if !isAdapterRoute then
          [ ]
        else
          let
            sourceModule = { imports = sourceModules; };
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
                [ freeformMod adapterMod ]
              else
                [ freeformMod ];
          in
          [
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
            }
          ];
      wrappedModules =
        if modulesWithAdapter == [ ] then
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
    {
      classImports = acc.classImports // {
        ${route.intoClass} = (acc.classImports.${route.intoClass} or [ ]) ++ wrappedModules;
      };
      inherit (acc) perScope;
    };

  # Main entry: dedup routes, fold applying each.
  applyRoutes =
    {
      scopedRoutes,
      wrappedPerScope,
      classImports,
      scopeContexts ? { },
      ctx ? { },
      fxResolve ? null,
      rootScopeId ? null,
      buildForwardAspect ? null,
    }:
    let
      rawRoutes = lib.concatLists (lib.attrValues scopedRoutes);

      # Dedup adapter routes by adapterKey@scope.
      childScopeKeys = builtins.foldl' (
        acc: r:
        let
          ak = r.adapterKey or null;
        in
        if ak != null && rootScopeId != null && r.sourceScopeId != rootScopeId then
          acc // { ${ak} = true; }
        else
          acc
      ) { } rawRoutes;

      allRoutes =
        let
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

      isDenDefaultModule =
        mod:
        let
          k = mod.key or mod._file or "";
        in
        lib.hasSuffix "@default" k;
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
          applySimpleRoute acc { inherit route wrappedPerScope; }
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
