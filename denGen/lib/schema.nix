# den.lib.schema.mkInstanceType options kind -> instance submodule type.
# Docs: reference/lib.mdx "mkInstanceType options kind" (options: extraModules, strict, specialArgs);
# guides/custom-entity-kinds.mdx s2 (strict=false => open instance).
denGen: {
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
            imports = (kind.imports or [ ]) ++ extraModules;
          }
          // (if strict then { } else { freeformType = t.lazyAttrsOf t.raw; })
        );
    };
}
