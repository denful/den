# Shared state mutation helpers for scoped pipeline fields.
{
  # Append an item to a scoped list field.
  scopedAppend =
    state: field: scope: item:
    state
    // {
      ${field} =
        _:
        let
          all = state.${field} null;
        in
        all // { ${scope} = (all.${scope} or [ ]) ++ [ item ]; };
    };

  # Merge attrs into a scoped attrset field.
  scopedMerge =
    state: field: scope: attrs:
    state
    // {
      ${field} =
        _:
        let
          all = state.${field} null;
        in
        all // { ${scope} = (all.${scope} or { }) // attrs; };
    };
}
