# Aspect-policy effect constructors (reference/policies.mdx s include); inert descriptors read by route.nix.
denGen: {
  effects.include = x: { __effect = "include"; value = x; };
}
