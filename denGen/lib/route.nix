# Per-host nixos module list: host closure first, then users, each aspect's user part before its nixos part (design-gen.md §3.8-9).
# `host` is the host entity (view.nix); users' entities come from host.users.
denGen: {
  route =
    aspects: host: users:
    let
      cl = denGen.closure aspects;
      userEnt = u: host.users.${u} // { inherit host; };
      argsOf = u: { inherit host; user = userEnt u; };
      nixosOf = args: a: if a.content ? nixos then [ (denGen.content.classModule args a.content.nixos) ] else [ ];
      userClosure =
        u:
        let
          r = aspects."${u}@${host.name}" or aspects.${u} or null;
        in
        (if r == null then [ ] else cl r) ++ policyAdds u;
      # Aspect policies of the host closure fire at user scope; include effects add aspects (inline class attrs -> synthetic "<policy>#<i>").
      # shortcut: no gen.program stratification (R1), policies of policy-included aspects and per-scope dedup come later.
      policyAdds =
        u:
        let
          fire = p: let r = p.fn (builtins.intersectAttrs (builtins.functionArgs p.fn) (argsOf u)); in if builtins.isList r then r else [ r ];
          ready = p: builtins.all (n: (argsOf u) ? ${n}) (builtins.attrNames (denGen.genLib.filterAttrs (_: opt: !opt) (builtins.functionArgs p.fn)));
          eff = builtins.concatMap (p: builtins.genList (i: { inherit p i; e = builtins.elemAt (fire p) i; }) (builtins.length (fire p))) (builtins.filter ready (builtins.concatMap (a: a.policyIncs) (cl aspects.${host.name})));
          inc = x:
            if (x.e.__effect or null) != "include" then [ ]
            else if x.e.value ? name then cl aspects.${x.e.value.name}
            else if x.e.value ? includes then builtins.concatMap (b: cl aspects.${b.name}) x.e.value.includes
            else [ { name = "${x.p.name}#${toString x.i}"; content = x.e.value; includes = [ ]; quirks = { }; policyIncs = [ ]; } ];
        in
        builtins.concatMap inc eff;
      userPart = u: a: { users.users.${u} = denGen.flatten (argsOf u) [ a.content.user ]; };
      # den.default is walked in both scopes, first (docs silent on order); its nixos lands once, in the host list.
      defaultCl = cl aspects.default;
      defaultUser = u: map (userPart u) (builtins.filter (a: a.content ? user) defaultCl);
      userModules = u: defaultUser u ++ map (userPart u) (builtins.filter (a: a.content ? user) (userClosure u));
      # default parts whose fn needs `user` bind per user scope and are skipped at host scope
      needsUser =
        a:
        let
          fnNeeds = v: (builtins.isFunction v || (builtins.isAttrs v && v ? __functor)) && (denGen.genLib.functionArgs v) ? user;
          go = v: fnNeeds v || (builtins.isAttrs v && builtins.isList (v.imports or null) && builtins.any go v.imports);
        in
        a.content ? nixos && go a.content.nixos;
      forUser =
        u:
        defaultUser u
        ++ builtins.concatMap (nixosOf (argsOf u)) (builtins.filter needsUser defaultCl)
        ++ builtins.concatMap (
          a: (if a.content ? user then [ (userPart u a) ] else [ ]) ++ nixosOf (argsOf u) a
        ) (userClosure u);
    in
    {
      inherit userModules;
      # home-manager.users.<u> gets default's then the user closure's homeManager parts; HM nixos module once, only if some user opts in.
      hm =
        inputs: hmUsers:
        let
          hmOf = u: a: if a.content ? homeManager then [ (denGen.content.classModule (argsOf u) a.content.homeManager) ] else [ ];
        in
        if hmUsers == [ ] then
          [ ]
        else
          [ inputs.home-manager.nixosModules.home-manager ]
          ++ map (u: { home-manager.users.${u}.imports = builtins.concatMap (hmOf u) (defaultCl ++ userClosure u); }) hmUsers;
      modules = builtins.concatMap (nixosOf { inherit host; }) (builtins.filter (a: !needsUser a) defaultCl ++ cl aspects.${host.name}) ++ builtins.concatMap forUser users;
    };
}
