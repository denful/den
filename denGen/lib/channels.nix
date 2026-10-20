# Quirk channels: pipe policies mark consumer hosts; emissions are aspect quirk keys read per host (G1: lazy cross-config).
denGen: {
  channels = {
    # shortcut: inert effect descriptors (docs explanation/policies.mdx s resolve); no routing yet, upgrade when policies fire.
    lib.policy.resolve = {
      __functor = _: bindings: { __effect = "resolve"; inherit bindings; };
      to = kind: bindings: { __effect = "resolve"; inherit kind bindings; };
    };
    lib.policy.include = denGen.effects.include;
    lib.policy.exclude = denGen.effects.exclude;
    lib.policy.route = denGen.effects.route;
    # when pred inner: guard over scope ctx only. hasAspect (closure membership) is NOT provided: reading it from a policy would cycle through the closure.
    lib.policy.when =
      pred: inner:
      let
        run = ctx: x:
          if builtins.isList x then builtins.concatMap (run ctx) x
          else if builtins.isAttrs x && x ? fn then run ctx x.fn
          else if builtins.isFunction x then run ctx (x (builtins.intersectAttrs (builtins.functionArgs x) ctx))
          else if builtins.isAttrs x && x ? __effect then [ x ]
          else [ (denGen.effects.include x) ];
      in
      {
        __functionArgs = builtins.functionArgs pred;
        __functor = _: ctx: if pred (builtins.intersectAttrs (builtins.functionArgs pred) ctx) then run ctx inner else [ ];
      };
    lib.policy.mkPolicy = name: fn: { __isPolicy = true; inherit name fn; };
    lib.policy.instantiate = x: { __effect = "instantiate"; value = x; };
    # policy value: pipe.from k [collect pred] -> { __pipe; key; preds }
    lib.policy.pipe = {
      from = key: steps: { __pipe = true; inherit key; preds = map (s: s.pred) steps; };
      collect = pred: { inherit pred; };
    };
    # modules for host h; allHosts = name -> { host; config (lazy final nixos config) }
    modules =
      world: allHosts: h: sibs:
      let
        call = f0: a: let f = if builtins.isAttrs f0 && (f0.__isPolicy or false) then f0.fn else f0; in if builtins.isFunction f then f (builtins.intersectAttrs (builtins.functionArgs f) a) else f;
        pipes = builtins.filter (p: builtins.isAttrs p && p ? __pipe) (
          builtins.concatMap (p: let r = call p { host = h; }; in if builtins.isList r then r else [ r ]) world.schema.host.includes
        );
        # self first, then sibling scopes (same parent) in attrName order (fleet.mdx:101-102)
        order = [ h.name ] ++ builtins.filter (n: n != h.name && allHosts ? ${n}) sibs;
        cl = n: denGen.closure world.aspects world.aspects.default ++ denGen.closure world.aspects world.aspects.${n};
        emit =
          k: n:
          let
            e = allHosts.${n};
            args = { inherit (e) host config; };
          in
          builtins.concatMap (a: if a.quirks ? ${k} then [ (call a.quirks.${k} args) ] else [ ]) (cl n);
        collected =
          p: builtins.concatMap (n: if builtins.all (pr: call pr { host = allHosts.${n}.host; } == true) p.preds then emit p.key n else [ ]) order;
      in
      map (p: { _module.args.${p.key} = collected p; }) pipes
      # docs quirks-and-pipes: a declared quirk is always bound, [] when nothing is emitted
      ++ map (k: { _module.args.${k} = [ ]; }) (builtins.filter (k: !builtins.any (p: p.key == k) pipes) (builtins.attrNames (world.quirks or { })));
  };
}
