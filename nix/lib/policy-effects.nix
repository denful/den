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
      splitIncludes =
        bindings:
        if bindings ? __includes then
          {
            includes = bindings.__includes;
            value = removeAttrs bindings [ "__includes" ];
          }
        else
          {
            includes = [ ];
            value = bindings;
          };
      mkResolve =
        shared: bindings:
        let
          s = splitIncludes bindings;
        in
        {
          __policyEffect = "resolve";
          __shared = shared;
          inherit (s) value includes;
        };
      mkResolveTo =
        shared: kind: bindings:
        let
          s = splitIncludes bindings;
        in
        {
          __policyEffect = "resolve";
          __shared = shared;
          __targetKind = kind;
          inherit (s) value includes;
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

  # Route class or trait content from one scope partition into a target class.
  # Tier 1 delivery — replaces den.provides.forward for the common case.
  route = spec: {
    __policyEffect = "route";
    value = spec;
  };

  # Request post-pipeline instantiation of an entity's class content.
  # The entity carries instantiate, intoAttr, mainModule metadata.
  instantiate = spec: {
    __policyEffect = "instantiate";
    value = spec;
  };

  # Tag a value with collisionPolicy = "class-wins".
  # When the value reaches a class module that also receives the same arg
  # from the module system (e.g., NixOS provides `lib`), the class value
  # wins silently — no collision error.
  pipelineOnly =
    value:
    if builtins.isAttrs value then
      value // { collisionPolicy = "class-wins"; }
    else
      {
        __functor = _: value;
        collisionPolicy = "class-wins";
      };
}
