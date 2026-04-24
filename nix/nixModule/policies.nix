{ den, lib, ... }:
let
  inherit (den.lib.policyTypes) policyType;
in
{
  options.den.policies = lib.mkOption {
    description = "Policies — declare directed edges between entity kinds with computed adjacency.";
    default = { };
    defaultText = lib.literalExpression "{ }";
    type = lib.types.lazyAttrsOf policyType;
  };

  # Global policy activation lives on den.default.policies (aspect schema).
  # No separate option needed — den.default is an aspect with freeform + typed options.
}
