# Policy dispatch — run policies against a context, return classified results.
{
  lib,
  resolveArgsSatisfied,
  classifyPolicyResult,
  extractTaggedEffects,
  hasEffects,
}:
let
  validEffectTypes = {
    resolve = true;
    include = true;
    exclude = true;
    route = true;
    instantiate = true;
    provide = true;
    pipe = true;
  };

  # Validate that each effect returned by a policy has a valid __policyEffect tag.
  validateEffects =
    policyName: rawEffects:
    lib.imap0 (
      i: eff:
      if !(builtins.isAttrs eff) then
        throw "den: policy '${policyName}' returned invalid effect at index ${toString i}: expected attrset, got ${builtins.typeOf eff}"
      else if !(eff ? __policyEffect) then
        throw "den: policy '${policyName}' returned invalid effect at index ${toString i}: missing __policyEffect — use den.lib.policy.resolve/include/exclude/route/instantiate/provide/pipe"
      else if !(validEffectTypes ? ${eff.__policyEffect}) then
        throw "den: policy '${policyName}' returned unknown effect type '${eff.__policyEffect}' at index ${toString i}"
      else
        eff
    ) rawEffects;

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
        effects = validateEffects entry.name rawEffects;
      }
    ) matching;

  # Combined dispatch returning classified + tagged results.
  mkDispatch =
    aspectPolicies: firedPolicies: resolveCtx:
    let
      allResults = dispatchAspect aspectPolicies firedPolicies resolveCtx;
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
