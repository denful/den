{ lib, ... }:
let
  # Build handler set from context.
  # Each key in ctx becomes a handler that resumes with the value.
  # has-handler queries the handler scope directly, including scoped
  # handlers from scope.provide.
  constantHandler =
    ctx:
    builtins.mapAttrs (
      _: value:
      { param, state }:
      {
        resume = value;
        inherit state;
      }
    ) ctx;

  # Dedup handler. Tracks seen keys in state.seen.
  # Each key maps to { ids } where ids is the accumulated aspect path-identity list.
  # Returns { isFirst, newAspectIds } where newAspectIds lists the given aspect
  # ids not previously recorded for this key.
  ctxSeenHandler = {
    "ctx-seen" =
      { param, state }:
      let
        # Accept both string (legacy) and attrset { key, aspects } params.
        key = if builtins.isString param then param else param.key;
        scopedKey =
          let
            scope = state.currentScope or null;
          in
          if scope == null || scope == "__unscoped" then key else "${scope}/${key}";
        aspects = if builtins.isString param then [ ] else param.aspects or [ ];
        seenSet = (state.seen or (_: { })) null;
        isFirst = !(seenSet ? ${scopedKey});
        previousAspects = if isFirst then [ ] else seenSet.${scopedKey}.ids;
        previousSet = lib.genAttrs previousAspects (_: true);
        newAspectIds = lib.filter (id: !(previousSet ? ${id})) aspects;
      in
      {
        resume = { inherit isFirst newAspectIds; };
        state = state // {
          seen =
            _:
            seenSet
            // {
              ${scopedKey} = {
                ids = previousAspects ++ newAspectIds;
              };
            };
        };
      };
  };

in
{
  inherit
    constantHandler
    ctxSeenHandler
    ;
}
