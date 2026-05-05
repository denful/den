{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx) identity;
  inherit (den.lib.aspects) isMeaningfulName;
in
{
  checkDedupHandler = {
    "check-dedup" =
      { param, state }:
      let
        child = param;
        originalName = child.name or "<anon>";
        isSyntheticName = lib.hasPrefix "<" originalName && lib.hasSuffix ">" originalName;
        rawDedupKey =
          if isMeaningfulName originalName && !isSyntheticName then identity.key child else null;
        scope = state.currentScope or "__unscoped";
        dedupKey = if rawDedupKey != null then "${scope}/${rawDedupKey}" else null;
        seen = (state.includeSeen or (_: { })) null;
        isDuplicate = dedupKey != null && seen ? ${dedupKey};
      in
      {
        resume = { inherit isDuplicate dedupKey; };
        state =
          if isDuplicate || dedupKey == null then
            state
          else
            state
            // {
              includeSeen = _: seen // { ${dedupKey} = true; };
            };
      };
  };
}
