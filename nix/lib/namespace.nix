name: sources:
{ config, lib, ... }:
let
  from = lib.flatten [ sources ];
  isOutput = builtins.elem true from;
  denfuls = map (lib.getAttrFromPath [
    "denful"
    name
  ]) (builtins.filter builtins.isAttrs from);

  # Strip _ aliases from external denful to prevent duplication on re-import.
  # The _ → provides alias in aspectSubmodule means evaluated configs contain
  # both _ and provides with identical content. Re-importing both causes
  # listOf options (like includes) to merge duplicates.
  stripAliases = lib.mapAttrs (
    _: v:
    if builtins.isAttrs v then
      builtins.removeAttrs v [
        "_"
        "__functor"
      ]
    else
      v
  );
  sourceModules = map (denful: { config.den.ful.${name} = stripAliases denful; }) denfuls;

  aliasModule = lib.mkAliasOptionModule [ name ] [ "den" "ful" name ];

  outputModule =
    if isOutput then
      {
        config.flake.denful.${name} = config.den.ful.${name};
      }
    else
      { };

  # Merge external source traits/classes into den.schema.
  # Local namespace traits/classes are collected by aspect-schema.nix.
  traitClassModule = {
    config.den.schema.traits = lib.mkMerge (map (denful: denful.traits or { }) denfuls);
    config.den.schema.classes = lib.mkMerge (map (denful: denful.classes or { }) denfuls);
    # Mirror into _classNames/_traitNames for cycle-free pipeline access.
    config.den._classNames = lib.mkMerge (
      map (denful: lib.genAttrs (builtins.attrNames (denful.classes or { })) (_: true)) denfuls
    );
    config.den._traitNames = lib.mkMerge (
      map (denful: lib.genAttrs (builtins.attrNames (denful.traits or { })) (_: true)) denfuls
    );
  };
in
{
  imports = sourceModules ++ [
    aliasModule
    outputModule
    traitClassModule
  ];
  config._module.args.${name} = config.den.ful.${name};
}
