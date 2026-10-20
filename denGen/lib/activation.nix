# Activation: ONE gen.program model per host tree; atom `a@s` = aspect a is a member of scope s (design-activation.md R1).
# R1 = zero behaviour change: candidates (static closures, delivery, one policy pass) arrive per scope in DFS order; the model decides membership, excludes by name.
denGen: {
  # scopes :: { <scope> = { cands :: [aspect]; ex :: [name]; }; }
  mkActivation =
    scopes:
    let
      atom = a: s: "${a}@${s}";
      rules = builtins.concatMap (
        s:
        map (a: { head = atom a.name s; pos = [ ]; neg = [ "x:${atom a.name s}" ]; relata = [ ]; }) scopes.${s}.cands
        ++ map (n: { head = "x:${atom n s}"; pos = [ ]; neg = [ ]; relata = [ ]; }) scopes.${s}.ex
      ) (builtins.attrNames scopes);
      model = denGen.gen.program.model {
        program = denGen.gen.program.program [ ] rules;
        interpretation = [ ];
        prior = null;
        complete = true;
      };
      checked = model.undefinedAtoms == [ ] || throw "den: aspects not stratified: ${toString model.undefinedAtoms}";
    in
    {
      # membership in scope s, candidate (DFS) order kept
      members = s: assert checked; builtins.filter (a: (model.resolve (atom a.name s)).included) scopes.${s}.cands;
    };
}
