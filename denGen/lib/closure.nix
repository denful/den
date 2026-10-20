# Includes closure: gen.program model = membership authority, DFS = order only (design-gen.md §3.6-7). Adapted from ren/lib/activation.nix.
denGen: {
  closure =
    aspects: root:
    let
      kids = a: map (b: aspects.${b.name}) a.includes;
      rules =
        [ { head = root.name; pos = [ ]; neg = [ ]; relata = [ ]; } ]
        ++ builtins.concatMap (
          a: map (b: { head = b.name; pos = [ a.name ]; neg = [ ]; relata = [ ]; }) a.includes
        ) (builtins.attrValues aspects);
      model = denGen.gen.program.model {
        program = denGen.gen.program.program [ ] rules;
        interpretation = [ ];
        prior = null;
        complete = true;
      };
      member = a: (model.resolve a.name).included;
      checked = model.undefinedAtoms == [ ] || throw "den: aspects not stratified: ${toString model.undefinedAtoms}";
      dfs =
        seen: a:
        if seen ? ${a.name} then
          seen
        else
          builtins.foldl' dfs (seen // { ${a.name} = a; order = (seen.order or [ ]) ++ [ a ]; }) (kids a);
      order = (dfs { } root).order;
    in
    assert checked;
    builtins.filter member order;
}
