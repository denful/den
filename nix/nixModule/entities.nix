{ den, lib, ... }:
{
  # Entity includes: per-kind list of aspects/functions included during
  # entity resolution. rootIncludes resolve before transitions.
  options.den.entityIncludes = lib.mkOption {
    description = "Per-entity-kind aspect includes for pipeline resolution.";
    default = { };
    type = lib.types.attrsOf (lib.types.listOf lib.types.raw);
  };

  # Entity provides: per-kind attrset of named providers.
  # Cross-provides (source.provides.${targetKey}) are used by the
  # transition handler for cross-entity aspect injection.
  options.den.entityProvides = lib.mkOption {
    description = "Per-entity-kind named providers for cross-entity injection.";
    default = { };
    type = lib.types.attrsOf (lib.types.lazyAttrsOf lib.types.raw);
  };
}
