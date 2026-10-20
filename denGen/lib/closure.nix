# Includes closure: gen.program model = membership authority, DFS = order only (design-gen.md §3.6-7). Adapted from ren/lib/activation.nix.
denGen: {
  closure =
    aspects: root:
    let
      # nested aspects are named `<parent>/<key>` and live inside their parent (view.nix); top-level names (incl. anons `n/i`) win.
      at = n: if aspects ? ${n} then aspects.${n} else builtins.foldl' (e: s: e.${s}) aspects (builtins.filter builtins.isString (builtins.split "/" n));
      kids = a: map (b: at b.name) a.includes;
      dfs =
        seen: a:
        if seen ? ${a.name} then
          seen
        else
          builtins.foldl' dfs (seen // { ${a.name} = a; order = (seen.order or [ ]) ++ [ a ]; }) (kids a);
      order = (dfs { } root).order;
      # only aspects reachable from root can be members, so rules are built from them
      rules =
        [ { head = root.name; pos = [ ]; neg = [ ]; relata = [ ]; } ]
        ++ builtins.concatMap (
          a:
          map (b: { head = b.name; pos = [ a.name ]; neg = [ "x:${b.name}" ]; relata = [ ]; }) a.includes
          ++ map (b: { head = "x:${b.name}"; pos = [ a.name ]; neg = [ ]; relata = [ ]; }) (a.excludes or [ ])
        ) order;
      model = denGen.gen.program.model {
        program = denGen.gen.program.program [ ] rules;
        interpretation = [ ];
        prior = null;
        complete = true;
      };
      member = a: (model.resolve a.name).included;
      checked = model.undefinedAtoms == [ ] || throw "den: aspects not stratified: ${toString model.undefinedAtoms}";
    in
    assert checked;
    builtins.filter member order;
}
