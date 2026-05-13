{
  lib,
  den,
  ...
}:
let
  schemaNames = builtins.attrNames (den.schema or { });

  # Canonical entity kind predicate: excludes conf, private keys,
  # and non-entity schema entries.
  schemaEntityKinds = builtins.filter (
    k: k != "conf" && !(lib.hasPrefix "_" k) && (den.schema.${k}.isEntity or false)
  ) schemaNames;

  # Variant for class-module.nix warnings: all schema-like arg names
  # (excludes conf, aspect, private keys) WITHOUT the isEntity check.
  # Used to detect missing den args in class module functions.
  schemaArgKinds = builtins.filter (
    k: k != "conf" && k != "aspect" && !(lib.hasPrefix "_" k)
  ) schemaNames;
  schemaEntityKindsSet = lib.genAttrs schemaEntityKinds (_: true);
in
{
  inherit schemaEntityKinds schemaEntityKindsSet schemaArgKinds;
}
