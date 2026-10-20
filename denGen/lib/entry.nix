denGen:
let
  # Only these leaves are captured; `den.users` etc. stay free for user-declared outer options.
  leaves = [ "hosts" "aspects" "schema" "policies" "quirks" "default" "systems" ];
  # Each outer definition becomes one Gen module rooted at the leaf (design-den-option.md option A).
  capture =
    lib: leaf:
    lib.mkOption {
      type = lib.mkOptionType {
        name = "denGenLeaf";
        emptyValue = { value = [ ]; };
        merge = _loc: defs: map (d: { _file = d.file; ${leaf} = d.value; }) defs;
      };
    };
  # flake-parts already declares `flake`, so only the plain-evalModules host adds it.
  mk =
    declareFlake:
    { lib, config, inputs, ... }:
    {
      options =
        lib.optionalAttrs declareFlake {
          flake = lib.mkOption {
            type = lib.types.lazyAttrsOf lib.types.raw;
            default = { };
          };
        }
        // {
          den = lib.genAttrs leaves (capture lib);
        };
      config._module.args.den = denGen.evalDen (lib.concatMap (l: config.den.${l}) leaves);
      config.flake.nixosConfigurations = denGen.hosts config._module.args.den inputs;
    };
in
{
  flakeModule = mk true;
  flakeModules.default = mk false;
}
