# Typed policy effect constructors.
# Policies return lists of these; the pipeline dispatches on __policyEffect.
{ lib, ... }:
{
  # Create a new context scope (fan-out). Each resolve creates a parallel
  # branch — a sibling context with new bindings merged into parent.
  # policy.resolve {} (empty bindings) is a no-op.
  resolve = bindings: {
    __policyEffect = "resolve";
    value = bindings;
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
