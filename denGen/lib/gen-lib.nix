# genLib: the `lib` the inner Gen eval sees (Gen only, no nixpkgs). Adapted from ren/lib/gen-lib.nix.
denGen: {
  genLib =
    builtins
    // denGen.gen.prelude
    // denGen.gen.merge
    // {
      # gen-types enum takes a name first (gen-types checkers.nix:1023).
      types = denGen.gen.merge.types // {
        enum = vs: denGen.gen.merge.types.enum "enum" vs;
      };
      evalModules =
        { modules }:
        denGen.gen.merge.evalModuleTree { specialArgs.lib = denGen.genLib; } modules;
    };
}
