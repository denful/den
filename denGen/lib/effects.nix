# Aspect-policy effect constructors (reference/policies.mdx s include); inert descriptors read by route.nix.
denGen: {
  effects.route = { fromClass, intoClass, path ? [ ] }: { __effect = "route"; inherit fromClass intoClass path; };
  effects.include = x: { __effect = "include"; value = x; };
}
