{ den, ... }:
let
  inherit (den.lib.aspects.fx.identity) aspectPath pathKey;

  # Add subtree (default) and .global variants to a constraint constructor.
  # mkFields returns the constraint record without scope.
  scoped = mkFields: {
    __functor = _: args: (mkFields args) // { scope = "subtree"; };
    global = args: (mkFields args) // { scope = "global"; };
  };

  exclude = scoped (
    ref:
    assert
      builtins.isAttrs ref || throw "fx.exclude: expected aspect attrset, got ${builtins.typeOf ref}";
    {
      type = "exclude";
      identity = pathKey (aspectPath ref);
    }
  );

  substituteFields =
    ref: replacement:
    assert
      builtins.isAttrs ref
      || throw "fx.substitute: expected aspect attrset for ref, got ${builtins.typeOf ref}";
    {
      type = "substitute";
      identity = pathKey (aspectPath ref);
      replacementName = replacement.name or "<anon>";
      getReplacement = _: replacement;
    };

  substitute = {
    __functor =
      _: ref: replacement:
      substituteFields ref replacement // { scope = "subtree"; };
    global = ref: replacement: substituteFields ref replacement // { scope = "global"; };
  };

  # Predicate-based filter. Excludes aspects where pred returns false.
  # pred receives the aspect attrset (with name, meta, includes, etc).
  filterBy = scoped (pred: {
    type = "filter";
    predicate = pred;
  });

in
{
  inherit exclude substitute filterBy;
}
