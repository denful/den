# Policy scope tree (design-policy.md R1). Fire membership = gen.program model per scope (Q2: one model per depth, tree finite).
# Q1: string atoms "p:<i>" / "x:<builtin>", unary rules (closure.nix:9-13 precedent). Q3: only schema.<kind>.includes fire
# (explanation/policies.mdx:129-130 also lists aspect includes; deferred, fleet uses schema includes only).
denGen: {
  policy =
    world:
    let
      lst = x: if builtins.isList x then x else [ x ];
      idOf = p: if builtins.isAttrs p && p ? __builtin then p.__builtin else null;
      # fires when every required arg is bound in the scope ctx (fleet.nix:19-21 resolveArgsSatisfied)
      ready = f: ctx: builtins.all (n: ctx ? ${n}) (builtins.attrNames (denGen.genLib.filterAttrs (_: opt: !opt) (denGen.genLib.functionArgs f)));
      model =
        rules:
        denGen.gen.program.model {
          program = denGen.gen.program.program [ ] rules;
          interpretation = [ ];
          prior = null;
          complete = true;
        };
      mk =
        kind: ctx: excl0: path:
        let
          sch = world.schema.${kind} or { };
          excl = excl0 ++ builtins.filter (x: x != null) (map idOf (sch.excludes or [ ])) ++ (if kind == "flake" then builtins.filter (x: x != null) (map idOf (world.schema.flake-system.excludes or [ ])) else [ ]);
          incs = sch.includes or [ ];
          # excludes are authoritative: an excluded identity's fire atom is negated (expl:131)
          rules =
            map (x: { head = "x:${x}"; pos = [ ]; neg = [ ]; relata = [ ]; }) excl
            ++ builtins.genList (i: { head = "p:${toString i}"; pos = [ ]; neg = let id = idOf (builtins.elemAt incs i); in if id != null && builtins.elem id excl then [ "x:${id}" ] else [ ]; relata = [ ]; }) (builtins.length incs)
            ++ map (n: { head = "b:${n}"; pos = [ ]; neg = if builtins.elem n excl then [ "x:${n}" ] else [ ]; relata = [ ]; }) builtinNames;
          m = model rules;
          fired = builtins.filter (i: let p = builtins.elemAt incs i; in (builtins.isFunction p || (p ? __functor && p ? __functionArgs)) && (m.resolve "p:${toString i}").included && ready p ctx) (builtins.genList (i: i) (builtins.length incs));
          effects = builtins.concatMap (i: let p = builtins.elemAt incs i; in map (e: if builtins.isAttrs e then e else { }) (lst (p (builtins.intersectAttrs (denGen.genLib.functionArgs p) ctx)))) fired;
          eff = k: builtins.filter (e: (e.__effect or null) == k) effects;
          key = e: "${e.kind}=${e.bindings.${e.kind}.name or ""}";
        in
        {
          inherit kind ctx;
          on = n: (m.resolve "b:${n}").included;
          instantiated = map (e: e.value.name) (eff "instantiate");
          children = map (e: mk e.kind (ctx // e.bindings) excl (path ++ [ (key e) ])) (builtins.filter (e: e ? kind && !(builtins.elem (key e) path)) (eff "resolve"));
        };
      builtinNames = [ "flake-to-systems" "system-to-os-outputs" "system-to-hm-outputs" "host-to-users" ];
      tree = mk "flake" { } [ ] [ ];
      scopes = s: [ s ] ++ builtins.concatMap scopes s.children;
      all = scopes tree;
      hostScopes = h: builtins.filter (s: s.kind == "host" && s.ctx.host.name == h.name) all;
    in
    {
      inherit tree;
      osOutputs = tree.on "system-to-os-outputs";
      instantiated = builtins.concatMap (s: s.instantiated) all;
      # declared host.users first, then resolved user children of every scope of that host
      usersOf = h: h.users // builtins.listToAttrs (builtins.concatMap (hs: map (u: { name = u.ctx.user.name; value = u.ctx.user; }) (builtins.filter (s: s.kind == "user") (scopes hs))) (hostScopes h));
      # same parent scope; no scope for h (no fleet) means all hosts
      siblingsOf = h: allNames:
        let p = builtins.filter (s: builtins.any (c: c.kind == "host" && c.ctx.host.name == h.name) s.children) all;
        in if p == [ ] then allNames else map (c: c.ctx.host.name) (builtins.filter (c: c.kind == "host") (builtins.head p).children);
    };
}
