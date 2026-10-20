# den.lib.parametric: deprecated identity passthroughs (reference/lib-deprecated.mdx); the pipeline binds scope args itself, content.nix does it here.
denGen: {
  parametric =
    let
      id = a: a;
    in
    {
      __functor = _: id;
      atLeast = id;
      exactly = id;
    };
}
