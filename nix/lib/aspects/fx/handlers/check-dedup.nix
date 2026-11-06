{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx) identity;
  inherit (den.lib.aspects) isMeaningfulName isSyntheticName;
in
{
  checkDedupHandler = {
    "check-dedup" =
      { param, state }:
      let
        child = param;
        originalName = child.name or "<anon>";
        rawDedupKey =
          if isMeaningfulName originalName && !(isSyntheticName originalName) then
            identity.key child
          else
            null;
        scope = state.currentScope or "__unscoped";
        dedupKey = if rawDedupKey != null then "${scope}/${rawDedupKey}" else null;
        seen = (state.includeSeen or (_: { })) null;
        # Under a cross-provider include (aspect/provide.nix) a repeat is walked
        # again, so its locations record the provenance (class-collector.nix);
        # emission dedup keeps the content single.
        underProvide = builtins.any (lib.hasInfix "den-provides-to-host=") (
          ((state.scopedIncludesChain or (_: { })) null).${scope} or [ ]
        );
        isDuplicate = dedupKey != null && seen ? ${dedupKey} && !underProvide;
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
