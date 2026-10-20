# Aspect-policy effect constructors (reference/policies.mdx s include); inert descriptors read by route.nix.
denGen: {
  effects.route = { fromClass, intoClass, path ? [ ], ... }@spec: { __effect = "route"; inherit fromClass intoClass path; } // (if spec ? intoPath then { inherit (spec) intoPath; } else { });
  effects.exclude = x: { __effect = "exclude"; value = x; };
  effects.include = x: { __effect = "include"; value = x; };
}
