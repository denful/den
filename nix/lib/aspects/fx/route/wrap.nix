# Route module wrapping — path nesting, guards, adaptArgs.
{ lib, ... }:
let
  # Adapt a module's args when path is empty (top-level adaptArgs).
  adaptModule =
    adaptArgs: path: mod:
    if adaptArgs == null || path != [ ] then
      mod
    else if builtins.isFunction mod then
      args: mod (adaptArgs args)
    else
      mod;

  # Nest a module at a path using submodule evaluation with adapted specialArgs.
  nestWithAdaptArgs =
    path: adaptArgs: mod: args:
    let
      fullArgs = args // (args.config._module.args or { });
      adapted = adaptArgs fullArgs;
      sourceModules = if builtins.isAttrs mod && mod ? imports then mod.imports else [ mod ];
      evaluated = lib.evalModules {
        specialArgs = adapted;
        modules = [
          { config._module.freeformType = lib.types.lazyAttrsOf lib.types.unspecified; }
        ]
        ++ sourceModules;
      };
    in
    {
      config = lib.setAttrByPath path (
        builtins.removeAttrs evaluated.config [
          "_module"
          "warnings"
          "assertions"
        ]
      );
    };

  # Nest a module at a path by resolving imports with full outer args.
  nestPlain =
    path: mod: args:
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

  # Nest a module at a target path (dispatch between adapt and plain strategies).
  nestModule =
    path: adaptArgs: mod:
    if path == [ ] then
      mod
    else if adaptArgs != null then
      nestWithAdaptArgs path adaptArgs mod
    else
      nestPlain path mod;

  # Wrap a module with a conditional guard.
  guardModule =
    guard: mod:
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

  # Apply the adapt → nest → guard pipeline to a list of modules.
  wrapRouteModules =
    {
      modules,
      path,
      guard ? null,
      adaptArgs ? null,
    }:
    map (mod: guardModule guard (nestModule path adaptArgs (adaptModule adaptArgs path mod))) modules;

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
