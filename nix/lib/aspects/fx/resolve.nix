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
    fxResolve: ctx: scopeContexts: rootScopeId: scopedRoutes: acc:
    route.applyRoutes {
      inherit
        scopedRoutes
        scopeContexts
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
    in
    # Direct match: if sourceScopeId itself is in the scope tree.
    if sid != null && builtins.elem sid allScopeIds then
      sid
    else
      let
        entityName = spec.name or null;
        children = builtins.filter (
          scopeId: scopeId != sid && (scopeParent.${scopeId} or null) == sid
        ) allScopeIds;
        matchByName =
          if entityName != null then
            builtins.filter (scopeId: lib.hasInfix "=${entityName}" scopeId) children
          else
            [ ];
      in
      if matchByName != [ ] then
        builtins.head matchByName
      else if builtins.length children == 1 then
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

  # Phase 4: Apply entity instantiation.
  applyInstantiates =
    scopedInstantiates: perScope: scopeParent: classImports:
    let
      allInstantiates = lib.concatLists (lib.attrValues scopedInstantiates);
      allScopeIds = builtins.attrNames perScope;
      instantiateModules = lib.concatMap (
        spec:
        let
          hasOutput = (spec.intoAttr or [ ]) != [ ];
        in
        if !hasOutput then
          [ ]
        else
          let
            hostClass = spec.class or "nixos";
            # If the host was walked in this pipeline, extract the entire subtree's
            # modules (host scope + user scopes + route-delivered content).
            # Otherwise fall back to mainModule (triggers fxResolve — legacy path).
            # TODO: subtree extraction disabled pending identity fixes.
            # Uses mainModule (per-host fxResolve) as fallback.
            modules = [ spec.mainModule ];
            instantiateArgs =
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
            evaluated = spec.instantiate instantiateArgs;
          in
          [ { config = lib.setAttrByPath ([ "flake" ] ++ spec.intoAttr) evaluated; } ]
      ) allInstantiates;
    in
    classImports
    // {
      flake = (classImports.flake or [ ]) ++ instantiateModules;
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

      # Assemble pipe data into scope contexts before wrapping.
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
        applyRoutes (fxResolve mkPipeline) ctx augmentedScopeContexts result.state.rootScopeId
          (result.state.scopedRoutes null)
          phase2;
      scopeParent = result.state.scopeParent null;
      phase4 =
        applyInstantiates (result.state.scopedInstantiates null) phase3.perScope scopeParent
          phase3.classImports;
    in
    {
      imports = phase4.${class} or [ ];
    };
in
{
  inherit fxResolve wrapCollectedClasses;
}
