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
        merge = _loc: defs: map (d: if leaf == "aspects" || leaf == "default" then lower lib leaf d else { _file = d.file; ${leaf} = d.value; }) defs;
      };
    };
  # Inline `includes` fns become anonymous aspects `<parent>/<idx>` (nixos content = fn's nixos, bound later by content.nix)
  # and the include becomes a ref to it, before gen-aspects typing sees a closure (design-fleet G3 arm a).
  # shortcut: only the fn result's `nixos` is kept (user/other classes dropped); lift them when a fleet needs it.
  lower =
    lib: leaf: d:
    let
      # A bare fn DEFINITION of an aspect (top-level or under provides/_) is class content, like an inline include fn.
      # shortcut: only the fn result's `nixos` is kept, as for inline includes.
      bare = f: { nixos = lib.setFunctionArgs (args: (f (builtins.intersectAttrs (lib.functionArgs f) args)).nixos or { }) (lib.functionArgs f); };
      norm =
        a:
        if builtins.isFunction a then
          bare a
        else if builtins.isAttrs a then
          a // lib.genAttrs (builtins.filter (k: builtins.isAttrs (a.${k} or null)) [ "provides" "_" ]) (k: builtins.mapAttrs (_: norm) a.${k})
        else
          a;
      raw = if leaf == "default" then { default = d.value; } else d.value;
      aspectsOf = if builtins.isAttrs raw then builtins.mapAttrs (_: norm) raw else raw;
      inl = a: lib.imap0 (i: e: { inherit i e; }) (if builtins.isAttrs a && builtins.isList (a.includes or null) then a.includes else [ ]);
      anon = n: i: "${n}/${toString i}";
      # Keys exist for every include slot (elements stay unforced: they may reference `den`, which would cycle).
      anons = lib.concatMapAttrs (
        n: a:
        builtins.listToAttrs (
          map (x: {
            name = anon n x.i;
            value.nixos =
              if builtins.isFunction x.e then
                lib.setFunctionArgs (args: (x.e (builtins.intersectAttrs (lib.functionArgs x.e) args)).nixos or { }) (lib.functionArgs x.e)
              else
                { };
          }) (inl a)
        )
      ) aspectsOf;
    in
    if !builtins.isAttrs aspectsOf then
      { _file = d.file; ${leaf} = d.value; }
    else
      { den, ... }:
      let
        fix = n: a: a // { includes = map (x: if builtins.isFunction x.e then den.aspects.${anon n x.i} else x.e) (inl a); };
        strip = a: if builtins.isAttrs a then removeAttrs a [ "policies" ] else a;
        fixed = builtins.mapAttrs (n: a: strip (if builtins.isAttrs a && builtins.isList (a.includes or null) then fix n a else a)) aspectsOf;
        # policy fns live outside the typed aspect (gen-aspects reads policies.* as a nested aspect path); eval.nix overlays them back.
        recs = lib.concatMapAttrs (n: a: lib.optionalAttrs (builtins.isAttrs a && builtins.isAttrs (a.policies or null)) { ${n} = builtins.mapAttrs (p: fn: { __isPolicy = true; inherit fn; name = "${n}.${p}"; }) a.policies; }) aspectsOf;
      in
      {
        _file = d.file;
        aspects = anons // lib.optionalAttrs (leaf == "aspects") fixed;
        default = lib.optionalAttrs (leaf == "default") fixed.default;
        policyRecs = lib.optionalAttrs (leaf == "aspects") recs;
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
              modules = lib.concatMap (
                a: lib.optional (a.content ? homeManager) (denGen.content.classModule { home = h // { inherit name system; }; } a.content.homeManager)
              ) (cl den.aspects.default ++ cl (den.aspects.${name} or den.aspects.${lib.head (lib.splitString "@" name)}));
            }
          ) hs
        ) den.homes;
    };
in
{
  lowerDef = lower;
  flakeModule = mk true;
  flakeModules.default = mk false;
}
