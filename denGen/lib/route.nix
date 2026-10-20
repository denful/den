# Per-host nixos module list: host closure first, then users, each aspect's user part before its nixos part (design-gen.md §3.8-9).
denGen: {
  route =
    aspects: host: users:
    let
      cl = denGen.closure aspects;
      nixosOf = args: a: if a.content ? nixos then [ (denGen.content.classModule args a.content.nixos) ] else [ ];
      userClosure =
        u:
        let
          r = aspects."${u}@${host}" or aspects.${u} or null;
        in
        if r == null then [ ] else cl r;
      userPart = u: a: { users.users.${u} = denGen.flatten { inherit host; user = u; } [ a.content.user ]; };
      # den.default is walked in both scopes, first (docs silent on order); its nixos lands once, in the host list.
      defaultCl = cl aspects.default;
      defaultUser = u: map (userPart u) (builtins.filter (a: a.content ? user) defaultCl);
      userModules = u: defaultUser u ++ map (userPart u) (builtins.filter (a: a.content ? user) (userClosure u));
      forUser =
        u:
        defaultUser u
        ++ builtins.concatMap (
          a: (if a.content ? user then [ (userPart u a) ] else [ ]) ++ nixosOf { inherit host; user = u; } a
        ) (userClosure u);
    in
    {
      inherit userModules;
      # home-manager.users.<u> gets default's then the user closure's homeManager parts; HM nixos module once, only if some user opts in.
      hm =
        inputs: hmUsers:
        let
          hmOf = u: a: if a.content ? homeManager then [ (denGen.content.classModule { inherit host; user = u; } a.content.homeManager) ] else [ ];
        in
        if hmUsers == [ ] then
          [ ]
        else
          [ inputs.home-manager.nixosModules.home-manager ]
          ++ map (u: { home-manager.users.${u}.imports = builtins.concatMap (hmOf u) (defaultCl ++ userClosure u); }) hmUsers;
      modules = builtins.concatMap (nixosOf { inherit host; }) (defaultCl ++ cl aspects.${host}) ++ builtins.concatMap forUser users;
    };
}
