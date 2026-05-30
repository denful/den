# Shared state mutation helpers for scoped pipeline fields.
#
# Each field is stored as a thunk `_: attrset` so that nix-effects'
# deepSeq on state doesn't force all fields eagerly.  However, we
# must prevent closure *chains*: if each write wraps the previous
# thunk, reading the final value costs O(N) and N reads costs O(N²).
# Fix: materialise the previous value outside the thunk closure via let
# binding, so each read is O(1).
{
  # Append an item to a scoped list field.
  scopedAppend =
    state: field: scope: item:
    let
      all = (state.${field} or (_: { })) null;
      updated = all // {
        ${scope} = (all.${scope} or [ ]) ++ [ item ];
      };
    in
    state // { ${field} = _: updated; };

  # Append multiple items to a scoped list field.
  scopedAppendMany =
    state: field: scope: items:
    let
      all = (state.${field} or (_: { })) null;
      updated = all // {
        ${scope} = (all.${scope} or [ ]) ++ items;
      };
    in
    state // { ${field} = _: updated; };

  # Merge attrs into a scoped attrset field.
  scopedMerge =
    state: field: scope: attrs:
    let
      all = (state.${field} or (_: { })) null;
      updated = all // {
        ${scope} = (all.${scope} or { }) // attrs;
      };
    in
    state // { ${field} = _: updated; };
}
