denGen:
let
  # Only these leaves are captured; `den.users` etc. stay free for user-declared outer options.
  leaves = [ "hosts" "aspects" "schema" "policies" "quirks" "classes" "homes" "default" "systems" ];
  # Each outer definition becomes one Gen module rooted at the leaf (design-den-option.md option A).
  capture =
    lib: leaf:
    lib.mkOption {
      type = lib.mkOptionType {
        name = "denGenLeaf";
        emptyValue = { value = [ ]; };
        merge = _loc: defs: map (d: if leaf == "aspects" || leaf == "default" then lower lib leaf d else { _file = d.file; ${leaf} = if leaf == "policies" && builtins.isAttrs d.value then builtins.mapAttrs (name: v: if v.__isPolicy or false then v else { __isPolicy = true; inherit name; fn = v; }) d.value else d.value; }) defs;
      };
    };
  # Lowering lives in normalize.nix; this only shapes the Gen module (inline includes -> anon aspects, design-fleet G3 arm a).
  lower =
    lib: leaf: d:
    if leaf != "default" && !builtins.isAttrs d.value then
      { _file = d.file; ${leaf} = d.value; }
    else
      { den, ... }:
      let
        n = denGen.normalize lib leaf (denGen.view.cnfOf den) (if leaf == "default" then { default = d.value; } else d.value);
        fixed = n.fixed den;
      in
      {
        _file = d.file;
        aspects = n.anons // lib.optionalAttrs (leaf == "aspects") fixed;
        default = lib.optionalAttrs (leaf == "default") fixed.default;
        policyRecs = lib.optionalAttrs (leaf == "aspects") n.recs;
        rawFns = lib.optionalAttrs (leaf == "aspects") (lib.filterAttrs (_: builtins.isFunction) d.value);
        aspectPolicies = lib.optionalAttrs (leaf == "aspects" || leaf == "default") n.polIncs;
      };
  # flake-parts already declares `flake`, so only the plain-evalModules host adds it.
  mk =
    declareFlake:
    { lib, config, inputs, ... }@margs:
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
      config._module.args.den = denGen.evalDen (lib.concatMap (l: config.den.${l}) leaves ++ lib.optional (margs ? withSystem) { _module.args.withSystem = margs.withSystem; });
      config.flake.nixosConfigurations = denGen.hosts config._module.args.den inputs;
      # standalone homes: aspect named by the home (guides/standalone-home-manager.mdx), its homeManager parts
      config.flake.homeConfigurations =
        let
          den = config._module.args.den;
          cl = denGen.closure den.aspects;
        in
        lib.concatMapAttrs (
          system: hs:
          lib.mapAttrs (
            name: h:
            inputs.home-manager.lib.homeManagerConfiguration {
              pkgs = inputs.nixpkgs.legacyPackages.${system};
              modules =
                let
                  base = lib.head (lib.splitString "@" name);
                  args = { home = h // { inherit name system; }; user = h // { inherit system; name = base; userName = base; }; };
                  dcl = cl den.aspects.default;
                  scope = denGen.schemaCl den.schema den.aspects true "home" ++ lib.concatMap (n: lib.optionals (den.aspects ? ${n}) (cl den.aspects.${n})) (lib.unique [ name base ]);
                in
                lib.concatMap (a: lib.optional (a.content ? homeManager) (denGen.content.classModule args a.content.homeManager)) (
                  dcl ++ scope ++ denGen.routes dcl [ ] args (dcl ++ scope)
                );
            }
          ) hs
        ) den.homes;
    };
in
{
  lowerDef = lower;
  # key: a test importing den.flakeModule again must dedupe, not redeclare `flake`
  flakeModule = { key = "denGen:flakeModule"; imports = [ (mk true) ]; };
  flakeModules.default = mk false;
}
