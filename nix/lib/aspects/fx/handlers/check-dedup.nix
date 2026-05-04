{
  lib,
  den,
  ...
}:
let
  identity = den.lib.aspects.fx.identity;
  inherit (den.lib.aspects) isMeaningfulName;
  inherit (den.lib.aspects.fx.traceUtil) traceDetail;
in
{
  checkDedupHandler = {
    "check-dedup" =
      { param, state }:
      let
        child = param;
        originalName = child.name or "<anon>";
        isSyntheticName = lib.hasPrefix "<" originalName && lib.hasSuffix ">" originalName;
        childIdentity = identity.key (child);
        rawDedupKey = if isMeaningfulName originalName && !isSyntheticName then childIdentity else null;
        scope = state.currentScope or "__unscoped";
        dedupKey = if rawDedupKey != null then "${scope}/${rawDedupKey}" else null;
        seen = (state.includeSeen or (_: { })) null;
        isDuplicate = dedupKey != null && seen ? ${dedupKey};
      in
      {
        resume =
          let
            dk = if dedupKey != null then dedupKey else "null";
            cid = child.__ctxId or "null";
            dup = if isDuplicate then "yes" else "no";
          in
          traceDetail
            "check-dedup name=${originalName} identity=${childIdentity} dedupKey=${dk} isDup=${dup} ctxId=${cid}"
            {
              inherit isDuplicate dedupKey;
            };
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
