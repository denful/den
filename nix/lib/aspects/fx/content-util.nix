{ lib, ... }:
let
  # Definition values of a content wrapper, empty definitions dropped.
  defValues =
    rawValue:
    builtins.filter (v: !(builtins.isAttrs v && v == { })) (map (d: d.value) rawValue.__contentValues);

  # Unwrap to a list of values, with empty-set fallback to [{}].
  # Used by aspect emitClassModules which needs per-element processing.
  # Matches source order: list check first, then __contentValues, then singleton.
  #
  # Several definitions of one CLASS key collapse into a single module: the
  # module system merges them through `imports`, so the class sees one value.
  # Quirk data has no such merge — see unwrapContentValuesAll.
  unwrapContentValuesList =
    rawValue:
    if builtins.isList rawValue then
      rawValue
    else if builtins.isAttrs rawValue && rawValue ? __contentValues then
      let
        vals = defValues rawValue;
      in
      if builtins.length vals == 0 then
        [ { } ]
      else if builtins.length vals == 1 then
        [ (builtins.head vals) ]
      else
        [ { imports = vals; } ]
    else
      [ rawValue ];

  # Every definition, uncollapsed. Quirks accumulate rather than merge, so a
  # pipe key defined by several modules must reach assembly as one entry per
  # definition. Collapsing them into `{ imports = …; }` would hand consumers a
  # single value carrying none of the emitted data.
  unwrapContentValuesAll =
    rawValue:
    if builtins.isList rawValue then
      rawValue
    else if builtins.isAttrs rawValue && rawValue ? __contentValues then
      let
        vals = defValues rawValue;
      in
      if vals == [ ] then [ { } ] else vals
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
  # Unwrap a provides value by detecting its shape and applying context.
  # Handles __fn wrappers, __functor, bare functions, and plain attrsets.
  # Used by emitAspectPolicies for cross-entity provides translation.
  applyProvide =
    value: ctx:
    if builtins.isAttrs value && value ? __fn then
      value.__fn ctx
    # Aspect attrsets with includes are already structured — return as-is.
    # Their __functor (from aspectType.merge) is a user convenience, not
    # intended for provides resolution; calling it here would invoke
    # resolveAspectWith outside the pipeline where class is unavailable.
    else if builtins.isAttrs value && value ? includes then
      value
    else if builtins.isAttrs value && value ? __functor then
      (value.__functor value) ctx
    else if lib.isFunction value then
      value ctx
    else
      value;
in
{
  inherit
    unwrapContentValuesList
    unwrapContentValuesAll
    unwrapContentValuesForClassification
    applyProvide
    ;
}
