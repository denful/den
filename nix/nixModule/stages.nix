{ den, lib, ... }:
let
  inherit (den.lib.stageTypes) stageTreeType;
in
{
  options.den.stages = lib.mkOption {
    description = "Named scopes for binding behavior to pipeline stages.";
    default = { };
    defaultText = lib.literalExpression "{ }";
    type = lib.types.lazyAttrsOf stageTreeType;
  };

  # Entity includes: per-kind list of aspects/functions included during
  # entity resolution. Replaces den.stages.*.includes.
  options.den.entityIncludes = lib.mkOption {
    description = "Per-entity-kind aspect includes for pipeline resolution.";
    default = { };
    type = lib.types.attrsOf (lib.types.listOf lib.types.raw);
  };
}
