# <a/b> lookup (guides/angle-brackets.mdx): `den/x` -> battery x else den.x; `a/b` -> aspect a's key b, else a.provides.b.
denGen: {
  angle =
    world: _: name:
    let
      parts = builtins.filter builtins.isString (builtins.split "[/.]" name);
      rest = builtins.tail parts;
      step = a: s: if a ? ${s} then a.${s} else a.provides.${s};
      root = if rest != [ ] && world.batteries ? ${builtins.head rest} then world.batteries else world;
    in
    if builtins.head parts == "den" then builtins.foldl' step root rest else builtins.foldl' step world.aspects parts;
}
