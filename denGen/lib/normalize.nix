# One lowering pass: normAspect (value), classifyKey (aspect key), classifyInc (include element).
denGen: {
  normalize =
    lib: leaf: cnf: raw:
    let
      # fn aspects/includes are class content: each declared class key projects its own part of the fn result
      classes = builtins.filter (k: denGen.gen.aspects.keyCategory cnf k == "class") (builtins.attrNames cnf.keySemantics);
      bare = f: lib.genAttrs classes (cls: lib.setFunctionArgs (args: (f (builtins.intersectAttrs (lib.functionArgs f) args)).${cls} or { }) (lib.functionArgs f));
      # structural keys are never nested aspects; other keys go through Gen keyCategory (class/channel keys hold content)
      skip = [ "provides" "_" "includes" "excludes" "policies" "meta" ];
      classifyKey =
        a: k:
        if builtins.elem k [ "provides" "_" ] then
          if builtins.isAttrs (a.${k} or null) then "provides" else null
        else if !builtins.elem k skip && denGen.gen.aspects.keyCategory cnf k == null && builtins.isAttrs a.${k} && !(a.${k} ? _type) then
          "nested"
        else
          null;
      keysOf = a: kind: builtins.filter (k: classifyKey a k == kind) (builtins.attrNames a);
      mapKids =
        f: path: a:
        a
        // lib.genAttrs (keysOf a "provides") (k: builtins.mapAttrs (c: v: f "${path}/${c}" v) a.${k})
        // lib.genAttrs (keysOf a "nested") (k: f "${path}/${k}" a.${k});
      kidList =
        path: a:
        lib.concatMap (k: lib.mapAttrsToList (c: v: { p = "${path}/${c}"; inherit v; }) a.${k}) (keysOf a "provides")
        ++ map (k: { p = "${path}/${k}"; v = a.${k}; }) (keysOf a "nested");
      normAspect =
        path: a:
        if builtins.isFunction a then
          bare a
        else if builtins.isAttrs a then
          mapKids normAspect path a
        else
          a;
      # policy record or functor-with-args; a plain fn in den.default.includes also counts (shortcut: elsewhere fns cannot be compared by `excludes`)
      isPol = e: builtins.isAttrs e && ((e.__isPolicy or false) || (e ? __functor && e ? __functionArgs));
      inlineAttrs = e: builtins.isAttrs e && !(e ? key) && !isPol e;
      classifyInc = e: {
        policy = isPol e || (leaf == "default" && builtins.isFunction e);
        slot = if isPol e then null else if builtins.isFunction e || inlineAttrs e then "anon" else "ref";
      };
      inl = a: lib.imap0 (i: e: { inherit i e; inc = classifyInc e; }) (if builtins.isAttrs a && builtins.isList (a.includes or null) then a.includes else [ ]);
      anon = n: i: "${n}/${toString i}";
      tree = if builtins.isAttrs raw then builtins.mapAttrs normAspect raw else raw;
      # Keys exist for every include slot (elements stay unforced: they may reference `den`, which would cycle).
      anonsAt =
        n: a:
        builtins.listToAttrs (
          map (x: {
            name = anon n x.i;
            value = if builtins.isFunction x.e then bare x.e else if inlineAttrs x.e then x.e else { };
          }) (inl a)
        )
        // lib.foldl' (acc: k: acc // anonsAt k.p k.v) { } (if builtins.isAttrs a then kidList n a else [ ]);
      polsAt =
        n: a:
        {
          ${n} = map (x: if x.e ? __isPolicy then x.e else { fn = x.e; name = "${n}.when${toString x.i}"; }) (builtins.filter (x: x.inc.policy) (inl a));
        }
        // lib.foldl' (acc: k: acc // polsAt k.p k.v) { } (kidList n a);
    in
    {
      inherit tree;
      anons = lib.concatMapAttrs anonsAt tree;
      polIncs = lib.concatMapAttrs polsAt (lib.filterAttrs (_: builtins.isAttrs) tree);
      # include slots become refs to the hoisted anons; `policies` is stripped (eval.nix overlays recs back)
      fixed =
        den:
        let
          fix = n: a: a // { includes = map (x: if x.inc.slot == "anon" then den.aspects.${anon n x.i} else x.e) (builtins.filter (x: x.inc.slot != null) (inl a)); };
          fixTree = n: a: if builtins.isAttrs a then mapKids fixTree n (if builtins.isList (a.includes or null) then fix n a else a) else a;
          strip = a: if builtins.isAttrs a then removeAttrs a [ "policies" ] else a;
        in
        builtins.mapAttrs (n: a: strip (fixTree n a)) tree;
      recs = lib.concatMapAttrs (n: a: lib.optionalAttrs (builtins.isAttrs a && builtins.isAttrs (a.policies or null)) { ${n} = builtins.mapAttrs (p: fn: { __isPolicy = true; inherit fn; name = "${n}.${p}"; }) a.policies; }) tree;
    };
}
