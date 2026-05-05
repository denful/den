# Policy dispatch — run policies against a context, return classified results.
{
  lib,
  resolveArgsSatisfied,
  classifyPolicyResult,
  extractTaggedEffects,
  hasEffects,
}:
let
  # Dispatch global + schema policies against a context.
  dispatchDirect =
    allDirectPolicies: firedPolicies: resolveCtx:
    lib.concatLists (
      lib.mapAttrsToList (
        name: policy:
        if !resolveArgsSatisfied policy resolveCtx || firedPolicies ? ${name} then
          [ ]
        else
          let
            result = policy resolveCtx;
            rawEffects = if builtins.isList result then result else [ result ];
          in
          if rawEffects == [ ] then
            [ ]
          else
            [
              {
                policyName = name;
                effects = rawEffects;
              }
            ]
      ) allDirectPolicies
    );

  # Dispatch aspect policies against a context.
  # Note: caller passes the same aspectPolicies each iteration; Nix memoizes
  # attrsToList per attrset identity, so repeated calls are cheap.
  dispatchAspect =
    aspectPolicies: firedPolicies: resolveCtx:
    let
      entries = lib.attrsToList aspectPolicies;
      matching = builtins.filter (
        e: resolveArgsSatisfied e.value.fn resolveCtx && !(firedPolicies ? ${e.name})
      ) entries;
    in
    map (
      entry:
      let
        result = entry.value.fn resolveCtx;
        rawEffects = if builtins.isList result then result else [ result ];
      in
      {
        policyName = entry.name;
        effects = rawEffects;
      }
    ) matching;

  # Combined dispatch returning classified + tagged results.
  mkDispatch =
    allDirectPolicies: aspectPolicies: firedPolicies: resolveCtx:
    let
      allResults =
        dispatchDirect allDirectPolicies firedPolicies resolveCtx
        ++ dispatchAspect aspectPolicies firedPolicies resolveCtx;
      classified = map classifyPolicyResult allResults;
      tagged = extractTaggedEffects classified;
    in
    tagged
    // {
      enrichment = builtins.foldl' (acc: r: acc // r.mergedEnrichment) { } classified;
      firedNames = map (r: r.policyName) (builtins.filter hasEffects classified);
    };
in
{
  inherit dispatchAspect mkDispatch;
}
