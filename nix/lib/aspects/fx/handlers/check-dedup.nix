{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx) identity;
  inherit (den.lib.aspects) isMeaningfulName isSyntheticName;
  provenance = import ./provenance.nix { inherit lib; };
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
        isDuplicate = dedupKey != null && seen ? ${dedupKey};
        # A repeat under a cross-provider include is not walked again, which
        # would apply its effects twice; it is recorded so the delivery reads
        # what its first walk emitted (handlers/provenance.nix).
        token = if isDuplicate then provenance.stackTokenOf state scope else null;
        allDeduped = (state.scopedProvenanceAspects or (_: { })) null;
        recordDeduped =
          s:
          if token == null then
            s
          else
            let
              updated = allDeduped // {
                ${scope} = (allDeduped.${scope} or { }) // {
                  ${token} = ((allDeduped.${scope} or { }).${token} or [ ]) ++ [ rawDedupKey ];
                };
              };
            in
            s // { scopedProvenanceAspects = builtins.seq (builtins.attrNames updated) (_: updated); };
      in
      {
        resume = { inherit isDuplicate dedupKey; };
        state =
          if isDuplicate then
            recordDeduped state
          else if dedupKey == null then
            state
          else
            state
            // {
              includeSeen = _: seen // { ${dedupKey} = true; };
            };
      };
  };
}
