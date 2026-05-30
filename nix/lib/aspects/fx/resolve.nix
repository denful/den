# Post-pipeline assembly: provides → routes → instantiates → output.
# Transforms raw pipeline state into final { imports = [...]; }.
{
  lib,
  den,
  ...
}:
let
  inherit (import ./wrap-classes.nix { inherit lib den; }) wrapCollectedClasses;
  inherit (import ./assemble-pipes.nix { inherit lib den; }) assemblePipes;
  route = import ./route { inherit lib den; };
  handlers = den.lib.aspects.fx.handlers;

  # Check if `ancestor` is an ancestor of `descendant` in the scopeParent tree.
  isAncestorOf =
    scopeParent: ancestor: descendant:
    let
      parent = scopeParent.${descendant} or null;
    in
    if parent == null || parent == descendant then
      false
    else
      parent == ancestor || isAncestorOf scopeParent ancestor parent;

  # Dedup provides by composite key (policyName/class/path).
  dedupProvides =
    raw:
    let
      go =
        seen: specs:
        if specs == [ ] then
          [ ]
        else
          let
            s = builtins.head specs;
            rest = builtins.tail specs;
            pn = s.__providePolicyName or null;
            key = if pn != null then "${pn}/${s.class}/${lib.concatStringsSep "/" (s.path or [ ])}" else null;
          in
          if key != null && seen ? ${key} then
            go seen rest
          else
            [ s ] ++ go (if key != null then seen // { ${key} = true; } else seen) rest;
    in
    go { } raw;

  # Phase 1: Wrap collected class imports per-scope.
  # Deduplicates modules with identical keys across scopes: when a shared
  # aspect is included by both host and user, it emits class modules in
  # both scopes.  The NixOS module system would eventually dedup by key,
  # but keeping duplicates wastes evaluation and can amplify lib.warn noise.
  wrapPerScope =
    ctx: scopeContexts: scopedClassImportsRaw:
    let
      wrappedPerScope = lib.mapAttrs (
        scopeId: scopeClasses: wrapCollectedClasses (scopeContexts.${scopeId} or ctx) scopeClasses
      ) scopedClassImportsRaw;
      # Fold scopes, deduplicating keyed modules (first occurrence wins).
      merged =
        let
          go =
            acc: scopeData:
            let
              allClasses = lib.unique (builtins.attrNames acc.classes ++ builtins.attrNames scopeData);
            in
            builtins.foldl' (
              a: cls:
              let
                existing = a.classes.${cls} or [ ];
                seenKeys = a.keys.${cls} or { };
                newMods = scopeData.${cls} or [ ];
                filtered = builtins.filter (
                  m:
                  let
                    k = m.key or null;
                  in
                  k == null || !(seenKeys ? ${k})
                ) newMods;
                addedKeys = builtins.foldl' (
                  ks: m:
                  let
                    k = m.key or null;
                  in
                  if k == null then ks else ks // { ${k} = true; }
                ) seenKeys filtered;
              in
              {
                classes = a.classes // {
                  ${cls} = existing ++ filtered;
                };
                keys = a.keys // {
                  ${cls} = addedKeys;
                };
              }
            ) acc allClasses;
          final = builtins.foldl' go {
            classes = { };
            keys = { };
          } (builtins.attrValues wrappedPerScope);
        in
        final.classes;
    in
    {
      classImports = merged;
      perScope = wrappedPerScope;
    };

  # Phase 2: Apply policy.provide — inject modules into target classes.
  applyProvides =
    ctx: scopeContexts: scopedProvides: acc:
    let
      allProvides = dedupProvides (lib.concatLists (lib.attrValues scopedProvides));
    in
    builtins.foldl' (
      prev: spec:
      let
        targetClass = spec.class;
        path = spec.path or [ ];
        sid = spec.sourceScopeId;
        scopeCtx = scopeContexts.${sid} or ctx;
        rawModule = if path == [ ] then spec.module else lib.setAttrByPath path spec.module;
        wrapped = den.lib.aspects.fx.aspect.wrapClassModule {
          inherit ctx;
          module = rawModule;
          aspectPolicy = null;
          globalPolicy = null;
        };
        wrappedMod =
          if wrapped.unsatisfied or false then
            [ ]
          else
            let
              loc = "${targetClass}@<provide>/${lib.concatStringsSep "/" path}";
            in
            [ (lib.setDefaultModuleLocation loc wrapped.module) ];
      in
      {
        classImports = prev.classImports // {
          ${targetClass} = (prev.classImports.${targetClass} or [ ]) ++ wrappedMod;
        };
        perScope = prev.perScope // {
          ${sid} = (prev.perScope.${sid} or { }) // {
            ${targetClass} = ((prev.perScope.${sid} or { }).${targetClass} or [ ]) ++ wrappedMod;
          };
        };
      }
    ) acc allProvides;

  # Phase 3: Apply routes.
  applyRoutes =
    fxResolve: ctx: scopeContexts: rootScopeId: scopeParent: scopedRoutes: acc:
    route.applyRoutes {
      inherit
        scopedRoutes
        scopeContexts
        scopeParent
        ctx
        rootScopeId
        fxResolve
        ;
      wrappedPerScope = acc.perScope;
      classImports = acc.classImports;
      inherit (handlers) buildForwardAspect;
    };

  # Phase 4: Apply entity instantiation.
  # Find the host scope ID for an instantiate spec.
  # register-instantiate records sourceScopeId = currentScope (the parent, e.g.
  # flake-system), but the entity's scope was created by resolve.to as a child.
  # Search child scopes of sourceScopeId matching the entity name.
  findHostScopeId =
    scopeParent: allScopeIds: spec:
    let
      sid = spec.sourceScopeId or null;
      entityName = spec.name or null;
      # Find child scopes of sourceScopeId (where resolve.to created the entity scope).
      children =
        if sid != null then
          builtins.filter (scopeId: scopeId != sid && (scopeParent.${scopeId} or null) == sid) allScopeIds
        else
          [ ];
      matchByName =
        if entityName != null then
          builtins.filter (scopeId: lib.hasInfix "=${entityName}" scopeId) children
        else
          [ ];
      # Among matches, prefer the shortest scope ID — the entity's own scope,
      # not a descendant (e.g., "host=lb-prod" over "host=lb-prod,user=deploy").
      bestMatch =
        if builtins.length matchByName <= 1 then
          matchByName
        else
          let
            sorted = builtins.sort (a: b: builtins.stringLength a < builtins.stringLength b) matchByName;
          in
          [ (builtins.head sorted) ];
    in
    if bestMatch != [ ] then
      builtins.head bestMatch
    # Single-child fallback only for entity specs (which carry mainModule).
    # Non-entity instantiate specs (e.g., collect-perSystem) should fall
    # through to sourceScopeId so they collect from the full subtree.
    else if spec ? mainModule && builtins.length children == 1 then
      builtins.head children
    else
      null;

  # Extract merged modules for a scope subtree (the scope + all descendants).
  # This produces the complete module set for a host: host-scope modules,
  # user-scope modules, and route-delivered modules — all in one list.
  extractSubtreeModules =
    perScope: scopeParent: rootScopeId: targetClass:
    let
      allScopeIds = builtins.attrNames perScope;
      # Collect all descendant scope IDs by walking scopeParent.
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
      # Collect modules from all subtree scopes, deduplicating by key.
      # Same aspect included at multiple scope levels (host default + user default)
      # produces identical static modules; first occurrence wins.
      # Named modules carry `key`; anon modules carry `_file` from setDefaultModuleLocation.
      raw = lib.concatMap (sid: perScope.${sid}.${targetClass} or [ ]) subtreeScopes;
      deduped =
        let
          go =
            seen: mods:
            if mods == [ ] then
              [ ]
            else
              let
                m = builtins.head mods;
                rest = builtins.tail mods;
                k = m.key or null;
              in
              if k != null && seen ? ${k} then
                go seen rest
              else
                [ m ] ++ go (if k != null then seen // { ${k} = true; } else seen) rest;
        in
        go { } raw;
    in
    if deduped == [ ] then null else deduped;

  # Build instantiateArgs for a spec without calling spec.instantiate.
  # Factored out so both applyInstantiates and hostConfigs can reuse it.
  mkInstantiateArgs =
    {
      augmentedScopeContexts,
      scopedClassImportsRaw,
      scopedProvides,
      scopedRoutes,
      scopeParent,
      scopeEntityClass ? (_: { }),
      fxResolveFn,
      ctx,
    }:
    spec:
    let
      allScopeIds = builtins.attrNames augmentedScopeContexts;
      hostClass = spec.class or "nixos";
      rawHostScopeId = findHostScopeId scopeParent allScopeIds spec;
      hostScopeId = if rawHostScopeId != null then rawHostScopeId else spec.sourceScopeId;
      preWalkedModules =
        if hostScopeId != null then
          let
            isInSubtree =
              sid:
              sid == hostScopeId
              || (
                let
                  parent = scopeParent.${sid} or null;
                in
                parent != null && parent != sid && isInSubtree parent
              );
            isAncestor =
              sid:
              let
                parent = scopeParent.${hostScopeId} or null;
              in
              sid == parent || (parent != null && parent != hostScopeId && isAncestorOf scopeParent sid parent);
            isRelevant = sid: isInSubtree sid || isAncestor sid;
            subtreeScopeIds = builtins.filter isInSubtree allScopeIds;
            relevantScopeIds = builtins.filter isRelevant allScopeIds;
            scopeEntityClassMap = scopeEntityClass null;
            subtreeContexts = lib.genAttrs subtreeScopeIds (
              sid:
              let
                base = augmentedScopeContexts.${sid};
                entityCls = scopeEntityClassMap.${sid} or null;
              in
              if !(base ? class) && entityCls != null then
                base // { class = entityCls; }
              else if !(base ? class) then
                base // { class = hostClass; }
              else
                base
            );
            subtreeClassImports = lib.genAttrs subtreeScopeIds (sid: scopedClassImportsRaw.${sid} or { });
            subtreeProvides = lib.filterAttrs (sid: _: isRelevant sid) scopedProvides;
            subtreeRoutes = lib.filterAttrs (sid: _: isRelevant sid) scopedRoutes;
            relevantContexts = lib.genAttrs relevantScopeIds (sid: augmentedScopeContexts.${sid});
            subtreePhase1 = wrapPerScope ctx subtreeContexts subtreeClassImports;
            subtreePhase2 = applyProvides ctx relevantContexts subtreeProvides subtreePhase1;
            subtreePhase3 =
              applyRoutes fxResolveFn ctx relevantContexts hostScopeId scopeParent subtreeRoutes
                subtreePhase2;
          in
          extractSubtreeModules subtreePhase3.perScope scopeParent hostScopeId hostClass
        else
          null;
      modules =
        if preWalkedModules != null then
          preWalkedModules
        else
          lib.optional (spec ? mainModule) spec.mainModule;
    in
    if spec ? pkgs then
      {
        inherit (spec) pkgs;
        inherit modules;
      }
    else
      {
        inherit modules;
      }
      // lib.optionalAttrs (spec ? system) {
        modules = modules ++ [
          { nixpkgs.hostPlatform = lib.mkDefault spec.system; }
        ];
      };

  # Phase 4: Apply entity instantiation.
  # When hosts were walked in the flake pipeline (via resolve.to "host"),
  # re-run assembly phases per host subtree with the host as rootScopeId.
  # This produces correct routing (identical to per-host fxResolve) while
  # reusing the walk's scope data — including sibling visibility for pipe.collect.
  #
  # Lazy: spec.instantiate is NOT called eagerly. Each output leaf is a thunk
  # that calls spec.instantiate only when accessed (e.g., when someone reads
  # config.flake.nixosConfigurations.cortex). This avoids evaluating all hosts
  # when only one is needed.
  applyInstantiates =
    {
      scopedInstantiates,
      augmentedScopeContexts,
      scopedClassImportsRaw,
      scopedProvides,
      scopedRoutes,
      scopeParent,
      scopeEntityClass ? (_: { }),
      fxResolveFn,
      ctx,
    }:
    classImports:
    let
      mkArgs = mkInstantiateArgs {
        inherit
          augmentedScopeContexts
          scopedClassImportsRaw
          scopedProvides
          scopedRoutes
          scopeParent
          scopeEntityClass
          fxResolveFn
          ctx
          ;
      };

      allInstantiates = lib.concatLists (lib.attrValues scopedInstantiates);

      # Build spec descriptors: { path, system, spec } without calling instantiate.
      # concatMap is strict in the list but the instantiate thunk is deferred.
      specDescriptors = lib.concatMap (
        spec:
        let
          hasOutput = (spec.intoAttr or [ ]) != [ ];
        in
        if !hasOutput then
          [ ]
        else
          [
            {
              path = [ "flake" ] ++ spec.intoAttr;
              system = spec.system or null;
              inherit spec;
            }
          ]
      ) allInstantiates;

      # Disambiguate instantiate entries targeting the same output path from
      # different entities. When the same user name appears on multiple systems
      # (e.g. den.homes.x86_64-linux.ben + den.homes.aarch64-darwin.ben both
      # producing homeConfigurations.ben), lib.recursiveUpdate would deeply
      # merge the two independent module-system evaluations, corrupting both.
      # Fix: qualify each colliding entry's output name with its system so both
      # are accessible (e.g. homeConfigurations."ben@x86_64-linux").
      # Same-entity duplicates (e.g. fleet + direct policy) are left as-is
      # since they produce compatible modules.
      #
      # Only inspects path and system metadata — never touches spec.instantiate.
      disambiguated =
        let
          pathStr = builtins.concatStringsSep ".";
          grouped = builtins.foldl' (
            acc: entry:
            let
              key = pathStr entry.path;
            in
            acc // { ${key} = (acc.${key} or [ ]) ++ [ entry ]; }
          ) { } specDescriptors;
          resolve =
            _: entries:
            if builtins.length entries <= 1 then
              entries
            else
              let
                systems = map (e: e.system or null) entries;
                uniqueSystems = lib.unique systems;
                isMultiSystem = builtins.length uniqueSystems > 1;
              in
              if isMultiSystem then
                # Different systems: qualify each output name with @system.
                map (
                  e:
                  let
                    basePath = lib.init e.path;
                    baseName = lib.last e.path;
                  in
                  e // { path = basePath ++ [ "${baseName}@${e.system}" ]; }
                ) entries
              else
                # Same entity via multiple policy paths: deduplicate.
                let
                  entry = lib.last entries;
                in
                lib.warnIf (builtins.length entries > 1)
                  "den: multiple instantiate specs target ${builtins.concatStringsSep "." entry.path} on ${
                    if entry.system != null then entry.system else "unknown"
                  }; keeping last"
                  [ entry ];
        in
        lib.concatLists (lib.mapAttrsToList resolve grouped);

      # Build lazy output tree.  Each leaf calls spec.instantiate on first access.
      instantiateConfigs = map (
        entry: lib.setAttrByPath entry.path (entry.spec.instantiate (mkArgs entry.spec))
      ) disambiguated;
    in
    classImports
    // {
      flake =
        (classImports.flake or [ ])
        ++ lib.optional (instantiateConfigs != [ ]) {
          config = builtins.foldl' lib.recursiveUpdate { } instantiateConfigs;
        };
    };

  # Full resolution: run pipeline, then assemble output through all phases.
  fxResolve =
    mkPipeline:
    {
      class,
      self,
      ctx,
    }:
    let
      result = mkPipeline { inherit class; } { inherit self ctx; };
      scopeContexts = result.state.scopeContexts null;

      scopedClassImportsRaw = result.state.scopedClassImports null;
      scopeParent = result.state.scopeParent null;
      scopedProvides = result.state.scopedProvides null;
      scopedRoutes = result.state.scopedRoutes null;

      # Scan raw pipe values for config-dependent thunks (functions taking
      # { config, ... }).  If none exist, hostConfigs stays null and
      # assemblePipes skips cross-host instantiation entirely.
      isConfigDependent = val: builtins.isFunction val && (builtins.functionArgs val) ? config;
      hasAnyConfigThunk =
        let
          # Values may be lists of entries, raw functions, or pipe entry
          # records ({ __isPipeEntry; module = <fn>; ... }).
          checkVal =
            v:
            if builtins.isList v then
              builtins.any checkVal v
            else if builtins.isAttrs v && v ? module then
              isConfigDependent v.module
            else
              isConfigDependent v;
        in
        builtins.any (scopeImports: builtins.any checkVal (lib.attrValues scopeImports)) (
          lib.attrValues scopedClassImportsRaw
        );

      # Pipe-data-free host configs for cross-host config thunk resolution.
      # Only computed when config-dependent thunks actually exist in the pipe
      # data.  When null, resolveThunks in assemblePipes short-circuits.
      hostConfigs =
        if !hasAnyConfigThunk then
          null
        else
          let
            allInstantiates = lib.concatLists (lib.attrValues (result.state.scopedInstantiates null));
            allScopeIds = builtins.attrNames scopeContexts;
            specsByHost = builtins.listToAttrs (
              lib.concatMap (
                spec:
                let
                  hasOutput = (spec.intoAttr or [ ]) != [ ];
                  hostScopeId = if hasOutput then findHostScopeId scopeParent allScopeIds spec else null;
                in
                if hostScopeId == null then
                  [ ]
                else
                  [
                    {
                      name = hostScopeId;
                      value = spec;
                    }
                  ]
              ) allInstantiates
            );
            mkArgs = mkInstantiateArgs {
              augmentedScopeContexts = scopeContexts;
              inherit
                scopedClassImportsRaw
                scopedProvides
                scopedRoutes
                scopeParent
                ;
              scopeEntityClass = result.state.scopeEntityClass or (_: { });
              fxResolveFn = fxResolve mkPipeline;
              inherit ctx;
            };
          in
          lib.mapAttrs (_: spec: (spec.instantiate (mkArgs spec)).config) specsByHost;

      # Assemble pipe data into scope contexts before wrapping.
      # Local config thunks are marked for deferred resolution inside evalModules.
      # Cross-host config thunks (from pipe.collect) are resolved using hostConfigs.
      scopeEntityKind = (result.state.scopeEntityKind or (_: { })) null;
      augmentedScopeContexts = assemblePipes {
        inherit scopeContexts hostConfigs scopeEntityKind;
        scopedClassImports = scopedClassImportsRaw;
        scopedPipeEffects = result.state.scopedPipeEffects null;
        inherit scopeParent;
      };

      # Post-assembly drain: resolve deferred includes.
      # Two categories of deferred includes are drained here:
      # 1. Pipe-arg deferred: required args are pipe names, now available
      #    from assemblePipes.
      # 2. Enrichment-deferred: required args (e.g., isNixos) were provided
      #    by a parent scope's policy enrichment but weren't available when
      #    the child scope was walked. The drain inherits parent scope context
      #    to resolve these.
      drainedClassImportsRaw =
        let
          allDeferred = (result.state.scopedDeferredIncludes or (_: { })) null;
          inherit (den.lib.aspects.fx.keyClassification) classifyKeys;
          inherit (den.lib.aspects.fx.contentUtil) unwrapContentValuesList;
          # Build enriched context for a scope by inheriting parent enrichment.
          # Walks up scopeParent to find enrichment keys not present in the
          # scope's own context.
          # Walk up scopeParent to inherit enrichment from all ancestors.
          enrichedScopeCtx =
            scopeId:
            let
              ownCtx = augmentedScopeContexts.${scopeId} or { };
              inherit_ =
                sid:
                let
                  pid = scopeParent.${sid} or null;
                in
                if pid == null || pid == sid then
                  { }
                else
                  let
                    parentCtx = augmentedScopeContexts.${pid} or { };
                    grandparentCtx = inherit_ pid;
                  in
                  grandparentCtx // parentCtx;
              ancestorCtx = inherit_ scopeId;
              # Only inherit keys not already in the scope's own context.
              inherited = lib.filterAttrs (k: _: !(ownCtx ? ${k})) ancestorCtx;
            in
            ownCtx // inherited;
        in
        lib.foldl' (
          accImports: scopeId:
          let
            deferred = allDeferred.${scopeId} or [ ];
            scopeCtx = enrichedScopeCtx scopeId;
            # Drain all deferred includes whose args are now satisfied,
            # not just pipe-arg deferred ones.
            drainable = builtins.filter (d: builtins.all (k: scopeCtx ? ${k}) (d.requiredArgs or [ ])) deferred;
          in
          if drainable == [ ] then
            accImports
          else
            let
              newEntries = lib.concatMap (
                d:
                let
                  child = d.child;
                  classified = classifyKeys null child;
                in
                lib.concatMap (
                  k:
                  let
                    modules = unwrapContentValuesList child.${k};
                  in
                  map (module: {
                    __rawEntry = true;
                    class = k;
                    inherit module;
                    ctx = scopeCtx;
                    identity = child.name or "<deferred>";
                    aspectPolicy = child.meta.collisionPolicy or null;
                    globalPolicy = den.config.classModuleCollisionPolicy or "error";
                    isContextDependent = false;
                  }) modules
                ) classified.classKeys
              ) drainable;
            in
            builtins.foldl' (
              acc: entry:
              acc
              // {
                ${scopeId} = (acc.${scopeId} or { }) // {
                  ${entry.class} = ((acc.${scopeId} or { }).${entry.class} or [ ]) ++ [ entry ];
                };
              }
            ) accImports newEntries
        ) scopedClassImportsRaw (builtins.attrNames allDeferred);

      phase1 = wrapPerScope ctx augmentedScopeContexts drainedClassImportsRaw;
      phase2 = applyProvides ctx augmentedScopeContexts scopedProvides phase1;
      phase3 =
        applyRoutes (fxResolve mkPipeline) ctx augmentedScopeContexts result.state.rootScopeId scopeParent
          scopedRoutes
          phase2;
      phase4 = applyInstantiates {
        scopedInstantiates = result.state.scopedInstantiates null;
        scopeEntityClass = result.state.scopeEntityClass or (_: { });
        inherit
          augmentedScopeContexts
          scopedProvides
          scopedRoutes
          scopeParent
          ctx
          ;
        # Pass drained class imports so pipe-arg deferred aspects are
        # included in per-host subtree assembly.
        scopedClassImportsRaw = drainedClassImportsRaw;
        fxResolveFn = fxResolve mkPipeline;
      } phase3.classImports;
    in
    {
      imports = phase4.${class} or [ ];
    };

  # Like fxResolve but skips instantiation (phase 4).
  # Returns only class imports from phases 1-3 (wrap, provides, routes).
  # Use for nested resolution where entity instantiation is unwanted
  # (e.g., extracting homeManager modules from a host's aspect tree).
  fxResolveImports =
    mkPipeline:
    {
      class,
      self,
      ctx,
    }:
    let
      result = mkPipeline { inherit class; } { inherit self ctx; };
      scopeContexts = result.state.scopeContexts null;
      scopedClassImportsRaw = result.state.scopedClassImports null;

      augmentedScopeContexts = assemblePipes {
        inherit scopeContexts;
        scopedClassImports = scopedClassImportsRaw;
        scopedPipeEffects = result.state.scopedPipeEffects null;
        scopeParent = result.state.scopeParent null;
      };

      phase1 = wrapPerScope ctx augmentedScopeContexts scopedClassImportsRaw;
      phase2 = applyProvides ctx augmentedScopeContexts (result.state.scopedProvides null) phase1;
      phase3 =
        applyRoutes (fxResolveImports mkPipeline) ctx augmentedScopeContexts result.state.rootScopeId
          (result.state.scopeParent null)
          (result.state.scopedRoutes null)
          phase2;
    in
    {
      imports = phase3.classImports.${class} or [ ];
    };
in
{
  inherit fxResolve fxResolveImports wrapCollectedClasses;
}
