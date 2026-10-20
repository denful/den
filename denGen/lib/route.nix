# Per-host nixos module list: host closure first, then users, each aspect's user part before its nixos part (design-gen.md §3.8-9).
# `host` is the host entity (view.nix); users' entities come from host.users.
denGen: {
  # policy.route: fromClass content of the scope closure re-delivered as intoClass content (reference/policies.mdx route).
  # shortcut: only user/home scope fires routes; path != [] needs attrset (non-function) content.
  routes =
    defaultCl: hostBase: args: scope:
    let
      pols = builtins.attrValues (builtins.listToAttrs (map (p: { name = p.name; value = p; }) (builtins.concatMap (a: a.policyIncs) (defaultCl ++ hostBase ++ scope))));
      ready = p: builtins.all (n: args ? ${n}) (builtins.attrNames (denGen.genLib.filterAttrs (_: opt: !opt) (denGen.genLib.functionArgs p.fn)));
      effs = builtins.concatMap (p: let r = p.fn (builtins.intersectAttrs (denGen.genLib.functionArgs p.fn) args); in if builtins.isList r then r else [ r ]) (builtins.filter ready pols);
      wrap = path: c: builtins.foldl' (v: i: { ${builtins.elemAt path (builtins.length path - 1 - i)} = v; }) c (builtins.genList (i: i) (builtins.length path));
      one = e: {
        name = "route#${e.fromClass}->${e.intoClass}";
        content.${e.intoClass} = { imports = map (a: wrap (if e ? intoPath then (if builtins.isFunction e.intoPath then e.intoPath { } else e.intoPath) else e.path) a.content.${e.fromClass}) (builtins.filter (a: a.content ? ${e.fromClass}) scope); };
        includes = [ ]; quirks = { }; policyIncs = [ ];
      };
    in
    map one (builtins.filter (e: (e.__effect or null) == "route") effs);
  route =
    sch: aspects: host: users:
    let
      cl = denGen.closure aspects;
      # a host with no declared aspect contributes nothing (users are treated the same below)
      # schema.host.includes aspect refs join the host closure (policy elements fire separately)
      schemaRefs =
        let
          go = x:
            if builtins.isList x then builtins.concatMap go x
            else if builtins.isAttrs x && !(denGen.classifyInc x).policy && x ? name && aspects ? ${x.name} then cl aspects.${x.name}
            else [ ];
        in
        go (sch.host.includes or [ ]);
      hostBase = schemaRefs ++ (if aspects ? ${host.name} then cl aspects.${host.name} else [ ]);
      # schema.<kind>.includes policies (possibly nested in `includes` lists); non-policy elements are skipped
      schemaPols =
        kind:
        let
          go = x:
            if builtins.isList x then builtins.concatMap go x
            else if (denGen.classifyInc x).policy then [ (if x.__isPolicy or false then x else { name = "schema.${kind}"; fn = x; }) ]
            else if builtins.isAttrs x && builtins.isList (x.includes or null) then go x.includes
            else [ ];
        in
        go (sch.${kind}.includes or [ ]);
      # hasAspect over the policy-free closure (policy-added aspects excluded, else it would cycle)
      hostProv = (aspects.${host.name} or { }).provides or { };
      provCl = k: if builtins.isAttrs (hostProv.${k} or null) then cl hostProv.${k} else [ ];
      tuCl = provCl "to-users";
      # hasAspect reads membership m (scope -> names) of the previous activation pass (design-activation.md R2, PM ruling Q3c)
      hasFn = f: { __functor = _: f; forAnyClass = f; };
      names = map (b: b.name);
      hostE = m: host // { hasAspect = hasFn (a: builtins.elem a.name (m host.name)); };
      hostArgs = m: { host = hostE m; };
      # policy.exclude of host-closure/schema policies drops those aspects from the scope subtree (names; shortcut: not the excluder's exclusive subtree).
      excludedAt =
        args: pols:
        let
          ready = p: builtins.all (n: args ? ${n}) (builtins.attrNames (denGen.genLib.filterAttrs (_: opt: !opt) (denGen.genLib.functionArgs p.fn)));
          fire = p: let r = p.fn (builtins.intersectAttrs (denGen.genLib.functionArgs p.fn) args); in if builtins.isList r then r else [ r ];
        in
        map (e: e.value.name) (builtins.filter (e: (e.__effect or null) == "exclude" && e.value ? name) (builtins.concatMap fire (builtins.filter ready pols)));
      # schema.<kind>.excludes aspect refs: authoritative over includes (reference/schema.mdx, policies.mdx:245)
      schemaEx = kind: map (b: b.name) (builtins.filter (b: builtins.isAttrs b && b ? name && !(b.__isPolicy or false) && !(b ? __builtin)) (sch.${kind}.excludes or [ ]));
      hostEx = m: schemaEx "host" ++ excludedAt (hostArgs m) (builtins.concatMap (a: a.policyIncs) hostBase ++ schemaPols "host");
      hostCl = act.members host.name;
      userScope = u: "${u}@${host.name}";
      allUsers = users ++ builtins.attrNames host.users;
      scopeNames = [ host.name ] ++ map userScope allUsers;
      # hasAspect view of a scope: default + host members (+ the user scope's own); excluded aspects are absent
      memOf = a: s: names defaultCl ++ names (a.members host.name) ++ (if s == host.name then [ ] else names (a.members s));
      # pass -1: policy-free static closures
      userStatic = u: defaultCl ++ hostBase ++ tuCl ++ provCl u ++ (let r = aspects."${u}@${host.name}" or aspects.${u} or null; in if r == null then [ ] else cl r);
      m0 = s: (builtins.listToAttrs (map (u: { name = userScope u; value = names (userStatic u); }) allUsers) // { ${host.name} = names (defaultCl ++ hostBase ++ tuCl); }).${s};
      # pass k fires policies with hasAspect reading pass k-1 membership, until membership is unchanged; oscillation throws
      passBound = builtins.length (builtins.attrNames aspects) + 1;
      fix =
        k: m:
        let
          a = denGen.mkActivation (scopesOf m);
          m' = memOf a;
          same = builtins.all (s: builtins.sort builtins.lessThan (m s) == builtins.sort builtins.lessThan (m' s)) scopeNames;
        in
        if same then a else if k >= passBound then throw "den: policy activation did not converge" else fix (k + 1) m';
      act = fix 1 m0;
      mF = memOf act;
      # one model per host tree: host scope + one scope per user
      # policies of every aspect in scope s's previous-pass membership (policy-added ones included); synthetic names have none
      memPols = m: s: builtins.concatMap (n: if aspects ? ${n} then builtins.concatMap (b: if b.name == n then b.policyIncs else [ ]) (cl aspects.${n}) else [ ]) (m s);
      scopesOf =
        m:
        { ${host.name} = { cands = hostBase ++ tuCl ++ adds (hostArgs m) (schemaPols "host" ++ memPols m host.name); ex = hostEx m; }; }
        // builtins.listToAttrs (map (u: { name = userScope u; value = userCands m u; }) allUsers);
      userEnt = m: u: host.users.${u} // { host = hostE m; hasAspect = hasFn (a: builtins.elem a.name (m (userScope u))); };
      argsOf' = m: u: { host = hostE m; user = userEnt m u; };
      argsOf = argsOf' mF;
      nixosOf = args: a: if a.content ? nixos then [ (denGen.content.classModule args a.content.nixos) ] else [ ];
      userCands =
        m: u:
        let
          r = aspects."${u}@${host.name}" or aspects.${u} or null;
          pols = schemaPols "user" ++ memPols m (userScope u);
        in
        {
          cands = (if r == null then [ ] else cl r) ++ tuCl ++ provCl u ++ adds (argsOf' m u) pols;
          ex = hostEx m ++ schemaEx "user" ++ excludedAt (argsOf' m u) pols;
        };
      userClosure =
        u:
        let
          base = act.members (userScope u);
        in
        base ++ routes (argsOf u) (defaultCl ++ base);
      # Aspect policies of the host closure fire at user scope; include effects add aspects (inline class attrs -> synthetic "<policy>#<i>").
      # shortcut: no gen.program stratification (R1), policies of policy-included aspects and per-scope dedup come later.
      adds =
        args: pols:
        let
          fnArgs = p: denGen.genLib.functionArgs p.fn;
          fire = p: let r = p.fn (builtins.intersectAttrs (fnArgs p) args); in if builtins.isList r then r else [ r ];
          ready = p: builtins.all (n: args ? ${n}) (builtins.attrNames (denGen.genLib.filterAttrs (_: opt: !opt) (fnArgs p)));
          eff = builtins.concatMap (p: builtins.genList (i: { inherit p i; e = builtins.elemAt (fire p) i; }) (builtins.length (fire p))) (builtins.filter ready pols);
          declared = n: let r = builtins.foldl' (e: s: if builtins.isAttrs e && e ? ${s} then e.${s} else null) aspects (if aspects ? ${n} then [ n ] else builtins.filter builtins.isString (builtins.split "/" n)); in if r == null then throw "den: aspect ${n} not declared" else r;
          inc = x:
            if (x.e.__effect or null) != "include" then [ ]
            else if x.e.value ? name then cl (declared x.e.value.name)
            else if x.e.value ? includes then builtins.concatMap (b: cl aspects.${b.name}) x.e.value.includes
            else [ { name = "${x.p.name}#${toString x.i}"; content = x.e.value; includes = [ ]; quirks = { }; policyIncs = [ ]; } ];
        in
        builtins.concatMap inc eff;
      routes = denGen.routes defaultCl hostBase;
      userVal = u: a: denGen.flatten (argsOf u) [ a.content.user ];
      userPart = u: a: { users.users.${u} = userVal u a; };
      # fn aspects project every class key; an empty projection must not declare users.users.<u>
      isEmpty = v: if v._type or null == "merge" then builtins.all isEmpty v.contents else v == { };
      hasUser = u: a: a.content ? user && !isEmpty (userVal u a);
      # den.default is walked in both scopes, first (docs silent on order); its nixos lands once, in the host list.
      defaultCl = cl aspects.default;
      defaultUser = u: map (userPart u) (builtins.filter (hasUser u) defaultCl);
      userModules = u: defaultUser u ++ map (userPart u) (builtins.filter (hasUser u) (userClosure u));
      # default parts whose fn needs `user` bind per user scope and are skipped at host scope
      needsUser =
        a:
        let
          fnNeeds = v: (builtins.isFunction v || (builtins.isAttrs v && v ? __functor)) && (denGen.genLib.functionArgs v) ? user;
          go = v: fnNeeds v || (builtins.isAttrs v && builtins.isList (v.imports or null) && builtins.any go v.imports);
        in
        a.content ? nixos && go a.content.nixos;
      # provides.to-hosts of every aspect in a user's closure (incl. policy-added) runs once per user, landing in the host's nixos (where-config-lands.mdx)
      toHosts =
        u:
        builtins.concatMap (
          a: let p = (a.provides or { })."to-hosts" or null; in if builtins.isAttrs p then builtins.concatMap (nixosOf (argsOf u)) (cl p) else [ ]
        ) (userClosure u);
      # every host user gets users.users.<u> even with no user-class content
      forUser =
        u:
        [ { users.users.${u} = { }; } ]
        ++ toHosts u
        ++ defaultUser u
        ++ builtins.concatMap (nixosOf (argsOf u)) (builtins.filter needsUser defaultCl)
        ++ builtins.concatMap (
          a: (if hasUser u a then [ (userPart u a) ] else [ ]) ++ (if builtins.elem a.name (map (b: b.name) tuCl) then [ ] else nixosOf (argsOf u) a)
        ) (userClosure u);
    in
    {
      inherit userModules;
      # home-manager.users.<u> gets default's then the user closure's homeManager parts; HM nixos module once, only if some user opts in.
      hm =
        inputs: hmUsers:
        let
          hmOf = u: a: if a.content ? homeManager then [ (denGen.content.classModule (argsOf u) a.content.homeManager) ] else [ ];
          # host-aspects opt-in: host closure parts not already in the user's closure
          viaHost = u: let uc = userClosure u; seen = map (b: b.name) (defaultCl ++ uc); in
            if builtins.elem "host-aspects" (map (b: b.name) uc) then builtins.filter (a: !(builtins.elem a.name seen)) hostBase else [ ];
        in
        if hmUsers == [ ] then
          [ ]
        else
          [ inputs.home-manager.nixosModules.home-manager ]
          ++ map (u: { home-manager.users.${u}.imports = builtins.concatMap (hmOf u) (defaultCl ++ userClosure u ++ viaHost u ++ routes (argsOf u) (viaHost u)); }) hmUsers;
      modules = builtins.concatMap (nixosOf { inherit host; }) (builtins.filter (a: !needsUser a) defaultCl ++ hostCl) ++ builtins.concatMap forUser users;
    };
}
