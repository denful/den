# Route module wrapping — path nesting, guards, adaptArgs.
{ lib, ... }:
let
  # Wrap modules with path nesting, optional guard, optional adaptArgs.
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
          args:
          let
            fullArgs = args // (args.config._module.args or { });
            adapted = adaptArgs fullArgs;
            sourceModules = if builtins.isAttrs mod && mod ? imports then mod.imports else [ mod ];
            evaluated = lib.evalModules {
              specialArgs = adapted;
              modules = [
                { config._module.freeformType = lib.types.lazyAttrsOf lib.types.unspecified; }
              ] ++ sourceModules;
            };
          in
          { config = lib.setAttrByPath path (builtins.removeAttrs evaluated.config [ "_module" ]); }
        else
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
          { config = lib.setAttrByPath path resolvedMod; };

      guardModule =
        mod:
        if guard == null then
          mod
        else
          args:
          let
            inner = if builtins.isFunction mod then mod args else mod;
          in
          { config = lib.mkIf (guard args) (inner.config or inner); };
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
in
{
  inherit wrapRouteModules collectClassMods;
}
