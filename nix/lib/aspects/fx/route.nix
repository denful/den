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
      adaptModule =
        mod:
        if adaptArgs == null then
          mod
        else if builtins.isFunction mod then
          args: mod (adaptArgs args)
        else
          mod;

      nestModule =
        mod: if path == [ ] then mod else { config = lib.setAttrByPath path { imports = [ mod ]; }; };

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
  # - During the dual-write transition period, wrappedPerScope wrapping is
  #   redundant with the flat wrappedClassImports. Once flat state fields are
  #   removed (spec steps 7-8), wrappedClassImports should derive from
  #   wrappedPerScope directly.
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
          else
            wrappedPerScope.${route.sourceScopeId}.${route.fromClass} or [ ];
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
        wrappedModules =
          if sourceModules == [ ] then
            [ ]
          else if isTraitRoute then
            map guardWrap sourceModules
          else
            wrapRouteModules {
              modules = sourceModules;
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
