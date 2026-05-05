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
        # Policy-emitted includes use the policy name for dedup — stable across scopes.
        # This ensures the same policy doesn't emit duplicate anonymous includes
        # when it fires at multiple entity boundaries in a cascade.
        isPolicyInclude = lib.hasPrefix "<policy:" originalName;
        rawDedupKey =
          if isPolicyInclude then
            originalName
          else if isMeaningfulName originalName && !isSyntheticName then
            identity.key child
          else
            null;
        scope = state.currentScope or "__unscoped";
        # Policy includes dedup globally (no scope prefix) — the same policy
        # firing at multiple scopes should not produce duplicate includes.
        dedupKey =
          if rawDedupKey == null then
            null
          else if isPolicyInclude then
            rawDedupKey
          else
            "${scope}/${rawDedupKey}";
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
