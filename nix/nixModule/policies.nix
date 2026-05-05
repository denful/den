{ config, lib, ... }:
let
  inherit (config.den.lib.aspects.policyTypes) policyRegistryType;
in
{
  options.den.policies = lib.mkOption {
    description = "Policies — declare directed edges between entity kinds with computed adjacency.";
    default = { };
    defaultText = lib.literalExpression "{ }";
    type = policyRegistryType;
  };
}
