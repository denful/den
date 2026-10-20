# den.lib.schema.mkInstanceType options kind -> instance submodule type.
# Docs: reference/lib.mdx "mkInstanceType options kind" (options: extraModules, strict, specialArgs);
# guides/custom-entity-kinds.mdx s2 (strict=false => open instance).
denGen: {
  # Registry-level `hasAspect`/`resolved` on every instance (entities.mdx resolved); structural: kind includes only.
  # route.nix overrides hasAspect with the scope-projected closure where the scope is known.
  schema.entity = kind: let lib = denGen.genLib; in {
    options.resolved = lib.mkOption { type = denGen.genLib.types.raw; default = { }; };
    options.hasAspect = lib.mkOption {
      type = denGen.genLib.types.raw;
      default = a: builtins.elem (a.name or null) (map (b: if builtins.isAttrs b then b.name or null else null) (kind.includes or [ ]));
    };
  };
  schema.lib =
    let
      t = denGen.genLib.types;
    in
    {
      mkInstanceType =
        {
          extraModules ? [ ],
          strict ? true,
          # shortcut: specialArgs accepted but ignored, wire when a consumer needs it.
          specialArgs ? { },
        }:
        kind:
        t.submodule (
          {
            imports = (kind.imports or [ ]) ++ extraModules ++ [ (denGen.schema.entity kind) ];
          }
          // (if strict then { } else { freeformType = t.lazyAttrsOf t.raw; })
        );
    };
}
