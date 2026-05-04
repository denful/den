# Route application: reads scope-partitioned class data,
# wraps at target path, injects into target class bucket.
# Handles both simple routes (path nesting) and complex forward-derived
# routes (buildForwardAspect with adapters, guards, external sources).
{
  lib,
  den,
  ...
}:
let
  # Wrap modules with path nesting, optional guard, optional adaptArgs.
  # For path != [], works with both submodule targets and plain option namespaces.
  wrapRouteModules =
    {
      modules,
      path,
      guard ? null,
      adaptArgs ? null,
    }:
    let
      # For path = [], adaptArgs wraps function modules directly.
      # For path != [], adaptArgs is resolved at the outer scope in nestModule,
      # so adaptModule is only used for top-level routes.
      adaptModule =
        mod:
        if adaptArgs == null || path != [ ] then
          mod
        else if builtins.isFunction mod then
          args: mod (adaptArgs args)
        else
          mod;

      nestModule =
        mod:
        if path == [ ] then
          mod
        else if adaptArgs != null then
          # Submodule nesting with adapted args: evaluate source modules
          # in a freeform submodule with specialArgs, then place the
          # evaluated config at the target path. This handles both raw
          # module functions and wrapped module attrsets (from wrapCollectedClasses).
          args:
          let
            fullArgs = args // (args.config._module.args or { });
            adapted = adaptArgs fullArgs;
            sourceModules = if builtins.isAttrs mod && mod ? imports then mod.imports else [ mod ];
            evaluated = lib.evalModules {
              specialArgs = adapted;
              modules = [
                {
                  config._module.freeformType = lib.types.lazyAttrsOf lib.types.unspecified;
                }
              ]
              ++ sourceModules;
            };
          in
          {
            config = lib.setAttrByPath path (builtins.removeAttrs evaluated.config [ "_module" ]);
          }
        else
          # Plain nesting: resolve the source module's function imports with
          # full outer module args (including _module.args like pkgs), then
          # place the result at the target path. Works for both submodule
          # targets (users.users.<name>) and plain option namespaces (wsl).
          args:
          let
            fullArgs = args // (args.config._module.args or { });
            resolveImport = imp: if builtins.isFunction imp then imp fullArgs else imp;
            resolvedMod =
              if builtins.isAttrs mod && mod ? imports then
                lib.foldl' lib.recursiveUpdate { } (map resolveImport mod.imports)
              else if builtins.isFunction mod then
                mod fullArgs
              else
                mod;
          in
          {
            config = lib.setAttrByPath path resolvedMod;
          };

      guardModule =
        mod:
        if guard == null then
          mod
        else
          args:
          let
            inner = if builtins.isFunction mod then mod args else mod;
          in
          {
            config = lib.mkIf (guard args) (inner.config or inner);
          };
    in
    map (mod: guardModule (nestModule (adaptModule mod))) modules;

  # Collect class modules from a forward aspect (recursing into includes).
  collectClassMods =
    cls: aspect:
    let
      own = if aspect ? ${cls} then [ aspect.${cls} ] else [ ];
      nested = builtins.concatMap (collectClassMods cls) (aspect.includes or [ ]);
    in
    own ++ nested;

  # Apply all registered routes to produce additional class imports.
  # Returns { classImports, perScope } with route-produced modules merged in.
  #
  # Simple routes: path nesting with optional guard/adaptArgs.
  # Complex routes (__complexForward): full forward spec, uses buildForwardAspect
  # with per-scope source lookup, root fallback, and external resolution.
  applyRoutes =
    {
      scopedRoutes,
      wrappedPerScope,
      classImports,
      # Additional args for complex route handling:
      scopeContexts ? { },
      ctx ? { },
      fxResolve ? null,
      rootScopeId ? null,
      buildForwardAspect ? null,
    }:
    let
      rawRoutes = lib.concatLists (lib.attrValues scopedRoutes);

      # Dedup adapter routes by adapterKey@scope.
      # Suppress root-scope specs when child copies exist (child copies
      # handle the forward with scope isolation).
      allRoutes =
        let
          # Collect adapterKeys that have child-scope specs.
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

          go =
            seen: routes:
            if routes == [ ] then
              [ ]
            else
              let
                r = builtins.head routes;
                rest = builtins.tail routes;
                ak = r.adapterKey or null;
                # Suppress root-scope spec when child copies handle the same forward.
                isRedundantRoot =
                  ak != null && rootScopeId != null && r.sourceScopeId == rootScopeId && childScopeKeys ? ${ak};
                # Scope-specific dedup: same forward at different scopes must NOT
                # be deduped — each scope needs its own isolated execution.
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

      # Filter for shared root modules (den.default only).
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
          # Complex route: port of applyForwardSpecs logic.
          let
            spec = route;
            sid = spec.sourceScopeId;
            # Source modules: per-scope for child-scope forwards (scope isolation),
            # merged for root-scope forwards (aggregate/alias forwards unchanged).
            sourceModules =
              if rootScopeId != null && sid != rootScopeId then
                # Per-scope + filtered root fallback: only den.default's shared
                # modules (identity = "default") from root scope.
                let
                  ownModules = (acc.perScope.${sid} or { }).${spec.fromClass} or [ ];
                  rootModules = (acc.perScope.${rootScopeId} or { }).${spec.fromClass} or [ ];
                  sharedModules = builtins.filter isDenDefaultModule rootModules;
                in
                sharedModules ++ ownModules
              else
                acc.classImports.${spec.fromClass} or [ ];
            # If no source modules in the pipeline, resolve the forward's
            # source aspect directly. Handles forwards whose fromAspect
            # produces a synthetic aspect not walked during the pipeline.
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
            rawSourceModule = {
              imports = resolvedSourceModules;
            };
            sourceModule = spec.mapModule rawSourceModule;
            forwardAspect = buildForwardAspect spec sourceModule;
            newMods = collectClassMods spec.intoClass forwardAspect;
          in
          {
            classImports = acc.classImports // {
              ${spec.intoClass} = (acc.classImports.${spec.intoClass} or [ ]) ++ newMods;
            };
            # Track forward outputs per-scope for chained forward support.
            perScope = acc.perScope // {
              ${sid} = (acc.perScope.${sid} or { }) // {
                ${spec.intoClass} = ((acc.perScope.${sid} or { }).${spec.intoClass} or [ ]) ++ newMods;
              };
            };
          }
        else
          # Simple route: original Tier 1 logic.
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
                    config = lib.setAttrByPath route.path (_: {
                      imports = [ ];
                    });
                  })
                ]
              else
                [ ];
            # Tier 2 adapter wrapping: forward-derived routes with adapterKey
            # use submodule evaluation (specialArgs) for the source modules.
            isAdapterRoute = route.adapterKey or null != null;
            adapterWrapped =
              if !isAdapterRoute then
                [ ]
              else
                let
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
          }
      )
      {
        inherit classImports;
        perScope = wrappedPerScope;
      }
      allRoutes;
in
{
  inherit wrapRouteModules applyRoutes;
}
