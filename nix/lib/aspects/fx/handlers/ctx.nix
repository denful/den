# constantHandler: Handles <arg-name> effects — resumes with context values for parametric aspects.
# ctxSeenHandler: Handles ctx-seen — dedup tracking for context stages.
# State reads: seen | State writes: seen
{
  lib,
  den,
  ...
}:
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
  # Each key maps to its accumulated aspect list (not just boolean).
  # Returns { isFirst, newAspects } where newAspects lists aspects
  # not previously recorded for this key.
  ctxSeenHandler = {
    "ctx-seen" =
      { param, state }:
      let
        # Accept both string (legacy) and attrset { key, aspects } params.
        key = if builtins.isString param then param else param.key;
        aspects = if builtins.isString param then [ ] else param.aspects or [ ];
        seenSet = (state.seen or (_: { })) null;
        isFirst = !(seenSet ? ${key});
        previousAspects = if isFirst then [ ] else seenSet.${key};
        previousSet = lib.genAttrs previousAspects (_: true);
        newAspects = builtins.filter (a: !(previousSet ? ${a})) aspects;
      in
      {
        resume = { inherit isFirst newAspects; };
        state = state // {
          seen = _: seenSet // { ${key} = previousAspects ++ newAspects; };
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
