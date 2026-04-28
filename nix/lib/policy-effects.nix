# Typed policy effect constructors.
# Policies return lists of these; the pipeline dispatches on __policyEffect.
{ lib, ... }:
{
  # Create a new context scope (fan-out). Each resolve creates a parallel
  # branch — a sibling context with new bindings merged into parent.
  # policy.resolve {} (empty bindings) is a no-op.
  # policy.resolve.shared {} sets __shared = true for shared (non-isolated) fan-out.
  resolve =
    let
      mkResolve = shared: bindings: {
        __policyEffect = "resolve";
        __shared = shared;
        value = bindings;
      };
      mkResolveTo = shared: kind: bindings: {
        __policyEffect = "resolve";
        __shared = shared;
        __targetKind = kind;
        value = bindings;
      };
    in
    {
      __functor = _: mkResolve false;
      shared = {
        __functor = _: mkResolve true;
        # resolve.shared.to "kind" { bindings } — shared fan-out with explicit target.
        to = mkResolveTo true;
      };
      # resolve.to "kind" { bindings } — explicit target kind for routing.
      to = mkResolveTo false;
    };

  # Inject an aspect into the current resolution context.
  # Accepts aspect references and inline attrsets (coerced to anonymous aspects).
  include = aspect: {
    __policyEffect = "include";
    value = aspect;
  };

  # Remove/gate an aspect from the current resolution tree.
  # Context-matched: applies to all contexts matching the policy's signature.
  exclude = aspect: {
    __policyEffect = "exclude";
    value = aspect;
  };
}
