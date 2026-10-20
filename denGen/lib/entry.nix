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
      # Children of an aspect: provides/_ entries and nested aspects (non-class attr keys), at any depth.
      # shortcut: class keys are a fixed list; custom classes holding an `includes` list would be mistaken for nested aspects.
      skip = [ "provides" "_" "includes" "excludes" "policies" "meta" "nixos" "darwin" "user" "homeManager" ];
      provKeys = a: builtins.filter (k: builtins.isAttrs (a.${k} or null)) [ "provides" "_" ];
      nestedKeys = a: builtins.filter (k: !builtins.elem k skip && builtins.isAttrs a.${k} && !(a.${k} ? _type)) (builtins.attrNames a);
      mapKids =
        f: path: a:
        a
        // lib.genAttrs (provKeys a) (k: builtins.mapAttrs (c: v: f "${path}/${c}" v) a.${k})
        // lib.genAttrs (nestedKeys a) (k: f "${path}/${k}" a.${k});
      kidList =
        path: a:
        lib.concatMap (k: lib.mapAttrsToList (c: v: { p = "${path}/${c}"; inherit v; }) a.${k}) (provKeys a)
        ++ map (k: { p = "${path}/${k}"; v = a.${k}; }) (nestedKeys a);
      norm =
        path: a:
        if builtins.isFunction a then
          bare a
        else if builtins.isAttrs a then
          mapKids norm path a
        else
          a;
      raw = if leaf == "default" then { default = d.value; } else d.value;
      aspectsOf = if builtins.isAttrs raw then builtins.mapAttrs norm raw else raw;
      inl = a: lib.imap0 (i: e: { inherit i e; }) (if builtins.isAttrs a && builtins.isList (a.includes or null) then a.includes else [ ]);
      # inline class-content attrset include: not a ref (refs carry `key`) and not a policy record
      isPol = e: builtins.isAttrs e && ((e.__isPolicy or false) || (e ? __functor && e ? __functionArgs));
      isPolInc = e: isPol e || (leaf == "default" && builtins.isFunction e);
      inlineAttrs = e: builtins.isAttrs e && !(e ? key) && !isPol e;
      anon = n: i: "${n}/${toString i}";
      # Keys exist for every include slot (elements stay unforced: they may reference `den`, which would cycle).
      anonsAt =
        n: a:
        builtins.listToAttrs (
          map (x: {
            name = anon n x.i;
            value =
              if builtins.isFunction x.e then
                { nixos = lib.setFunctionArgs (args: (x.e (builtins.intersectAttrs (lib.functionArgs x.e) args)).nixos or { }) (lib.functionArgs x.e); }
              else if inlineAttrs x.e then
                x.e
              else
                { };
          }) (inl a)
        )
        // lib.foldl' (acc: k: acc // anonsAt k.p k.v) { } (if builtins.isAttrs a then kidList n a else [ ]);
      anons = lib.concatMapAttrs anonsAt aspectsOf;
      # policy elements of includes, hoisted per aspect (nested ones under their full path name)
      polsAt =
        n: a:
        {
          ${n} = map (x: if x.e ? __isPolicy then x.e else { fn = x.e; name = "${n}.when${toString x.i}"; }) (builtins.filter (x: isPolInc x.e) (inl a));
        }
        // lib.foldl' (acc: k: acc // polsAt k.p k.v) { } (kidList n a);
    in
    if !builtins.isAttrs aspectsOf then
      { _file = d.file; ${leaf} = d.value; }
    else
      { den, ... }:
      let
        fix = n: a: a // { includes = map (x: if builtins.isFunction x.e || inlineAttrs x.e then den.aspects.${anon n x.i} else x.e) (builtins.filter (x: !isPol x.e) (inl a)); };
        strip = a: if builtins.isAttrs a then removeAttrs a [ "policies" ] else a;
        fixTree = n: a: if builtins.isAttrs a then mapKids fixTree n (if builtins.isList (a.includes or null) then fix n a else a) else a;
        fixed = builtins.mapAttrs (n: a: strip (fixTree n a)) aspectsOf;
        # policy fns live outside the typed aspect (gen-aspects reads policies.* as a nested aspect path); eval.nix overlays them back.
        recs = lib.concatMapAttrs (n: a: lib.optionalAttrs (builtins.isAttrs a && builtins.isAttrs (a.policies or null)) { ${n} = builtins.mapAttrs (p: fn: { __isPolicy = true; inherit fn; name = "${n}.${p}"; }) a.policies; }) aspectsOf;
      in
      {
        _file = d.file;
        aspects = anons // lib.optionalAttrs (leaf == "aspects") fixed;
        default = lib.optionalAttrs (leaf == "default") fixed.default;
        policyRecs = lib.optionalAttrs (leaf == "aspects") recs;
        # shortcut: plain fns in den.default.includes count as policies; elsewhere functions cannot be compared, so `excludes` could not drop them.
        policyIncRecs = lib.optionalAttrs (leaf == "aspects" || leaf == "default") (lib.concatMapAttrs polsAt (lib.filterAttrs (_: a: builtins.isAttrs a) aspectsOf));
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
              modules =
                let
                  args = { home = h // { inherit name system; }; user = h // { inherit name system; }; };
                  dcl = cl den.aspects.default;
                  scope = cl (den.aspects.${name} or den.aspects.${lib.head (lib.splitString "@" name)});
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
  flakeModule = mk true;
  flakeModules.default = mk false;
}
