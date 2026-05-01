# Route application: reads scope-partitioned class/trait data,
# wraps at target path, injects into target class bucket.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx.pipeline) inheritTraits;

  # Wrap modules with path nesting, optional guard, optional adaptArgs.
  # For path != [], target option must be a submodule type.
  wrapRouteModules =
    {
      modules,
      path,
      guard ? null,
      adaptArgs ? null,
    }:
    let
      # For path = [], adaptArgs wraps function modules directly.
      # For path != [], adaptArgs is injected via _module.args in the submodule
      # definition (see nestModule), so adaptModule is only used for top-level routes.
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
          # Submodule nesting with adapted args: evaluate source module with
          # adaptArgs-provided specialArgs (pkgs, osConfig, etc.) via a freeform
          # evalModules, then inject the result as a submodule definition function
          # at the target path. The _: wrapper ensures NixOS treats it as a
          # submodule definition, creating the entry (e.g., users.users.tux).
          args:
          let
            adapted = adaptArgs args;
            freeformMod.config._module.freeformType = lib.types.lazyAttrsOf lib.types.unspecified;
            evaluated = lib.evalModules {
              specialArgs = adapted;
              modules = [
                freeformMod
                mod
              ];
            };
            cfg = builtins.removeAttrs evaluated.config [ "_module" ];
          in
          {
            config = lib.setAttrByPath path (_: cfg);
          }
        else
          # Plain nesting: evaluate source module via freeform evalModules,
          # then place the config at the target path. Works for both submodule
          # targets (users.users.<name>) and plain option namespaces (wsl).
          let
            freeformMod.config._module.freeformType = lib.types.lazyAttrsOf lib.types.unspecified;
            evaluated = lib.evalModules {
              modules = [
                freeformMod
                mod
              ];
            };
            cfg = builtins.removeAttrs evaluated.config [ "_module" ];
          in
          {
            config = lib.setAttrByPath path cfg;
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

  # Synthesize a NixOS module from trait data at a target path.
  # Unlike class routes, trait routes handle their own path nesting because
  # trait data is a plain value (list, map, scalar), not a NixOS module —
  # wrapRouteModules' submodule-based nesting doesn't apply.
  traitRouteModule =
    route: traitData:
    { ... }:
    {
      config = lib.setAttrByPath route.path traitData;
    };

  # Apply all registered routes to produce additional class imports.
  # Returns { classImports } with route-produced modules merged in.
  #
  # Design notes:
  # - Trait routes use inheritTraits (pipeline-time data only). Deferred traits
  #   (Tier 3 / runtime-evaluated) are intentionally excluded — they depend on
  #   moduleArgs which aren't available at route application time.
  applyRoutes =
    {
      scopedRoutes,
      wrappedPerScope,
      scopedTraits,
      scopeParent,
      traitSchemas,
      classImports,
    }:
    let
      allRoutes = lib.concatLists (lib.attrValues scopedRoutes);
    in
    builtins.foldl' (
      acc: route:
      let
        isTraitRoute = route ? fromTrait;
        scopeExists = wrappedPerScope ? ${route.sourceScopeId};
        sourceModules =
          if isTraitRoute then
            let
              strategy = (traitSchemas.${route.fromTrait} or { }).collection or "list";
              traitData = inheritTraits {
                inherit scopedTraits scopeParent;
              } route.sourceScopeId route.fromTrait strategy;
              emptyDefault = if strategy == "map" then { } else [ ];
            in
            if traitData == emptyDefault then [ ] else [ (traitRouteModule route traitData) ]
          else if !scopeExists then
            builtins.trace
              "den: route from '${route.fromClass}' — source scope '${route.sourceScopeId}' not found in pipeline (cross-pipeline routing requires fleet scope)"
              [ ]
          else
            wrappedPerScope.${route.sourceScopeId}.${route.fromClass} or [ ];
        adapterMod = route.adapterModule or null;
        modulesWithAdapter = if adapterMod == null then sourceModules else sourceModules ++ [ adapterMod ];
        # Trait route modules handle their own path nesting (via setAttrByPath)
        # because trait data is a plain value, not a NixOS submodule.
        # Class route modules go through wrapRouteModules for submodule nesting.
        # Both still apply guard wrapping if specified.
        guard = route.guard or null;
        guardWrap =
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
        # When adaptArgs is set with path nesting, always produce at least an
        # empty submodule definition so the target entry exists (e.g.,
        # users.users.tux). Other modules (home-manager) reference the entry.
        ensureEntry =
          if route.adaptArgs or null != null && route.path or [ ] != [ ] && modulesWithAdapter == [ ] then
            [
              (_: {
                config = lib.setAttrByPath route.path (_: { });
              })
            ]
          else
            [ ];
        wrappedModules =
          if modulesWithAdapter == [ ] then
            ensureEntry
          else if isTraitRoute then
            map guardWrap modulesWithAdapter
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
      }
    ) { inherit classImports; } allRoutes;
in
{
  inherit wrapRouteModules applyRoutes traitRouteModule;
}
