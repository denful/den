{ lib, ... }:
let
  # Unwrap aspectContentType's __contentValues wrapper to a single value.
  # Filters empty attrsets from multi-site defs, merges remainder.
  # Used by provides-compat.
  unwrapContentValues =
    rawValue:
    if builtins.isAttrs rawValue && rawValue ? __contentValues then
      let
        vals = builtins.filter (v: !(builtins.isAttrs v && v == { })) (
          map (d: d.value) rawValue.__contentValues
        );
      in
      if builtins.length vals == 0 then
        { }
      else if builtins.length vals == 1 then
        builtins.head vals
      else
        { imports = vals; }
    else
      rawValue;

  # Unwrap without filtering empty attrsets — preserves original semantics
  # for emitNestedAspect which did not filter empties.
  unwrapContentValuesRaw =
    rawValue:
    if builtins.isAttrs rawValue && rawValue ? __contentValues then
      let
        vals = map (d: d.value) rawValue.__contentValues;
      in
      if builtins.length vals == 1 then builtins.head vals else { imports = vals; }
    else
      rawValue;

  # Unwrap to a list of values, with empty-set fallback to [{}].
  # Used by aspect emitClassModules which needs per-element processing.
  # Matches source order: list check first, then __contentValues, then singleton.
  unwrapContentValuesList =
    rawValue:
    if builtins.isList rawValue then
      rawValue
    else if builtins.isAttrs rawValue && rawValue ? __contentValues then
      let
        vals = builtins.filter (v: !(builtins.isAttrs v && v == { })) (
          map (d: d.value) rawValue.__contentValues
        );
      in
      if builtins.length vals == 0 then
        [ { } ]
      else if builtins.length vals == 1 then
        [ (builtins.head vals) ]
      else
        [ { imports = vals; } ]
    else
      [ rawValue ];

  # Unwrap for key-classification inspection: merges attrset values
  # for sub-key detection, returns null for non-attrsets.
  unwrapContentValuesForClassification =
    rawValue:
    if builtins.isAttrs rawValue && rawValue ? __contentValues then
      let
        vals = map (d: d.value) rawValue.__contentValues;
        attrVals = builtins.filter builtins.isAttrs vals;
      in
      if attrVals != [ ] then builtins.foldl' (a: b: a // b) { } attrVals else null
    else if builtins.isAttrs rawValue then
      rawValue
    else
      null;
in
{
  inherit
    unwrapContentValues
    unwrapContentValuesRaw
    unwrapContentValuesList
    unwrapContentValuesForClassification
    ;
}
