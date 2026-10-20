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
      userModules = u: map (userPart u) (builtins.filter (a: a.content ? user) (userClosure u));
      forUser =
        u:
        builtins.concatMap (
          a: (if a.content ? user then [ (userPart u a) ] else [ ]) ++ nixosOf { inherit host; user = u; } a
        ) (userClosure u);
    in
    {
      inherit userModules;
      modules = builtins.concatMap (nixosOf { inherit host; }) (cl aspects.${host}) ++ builtins.concatMap forUser users;
    };
}
