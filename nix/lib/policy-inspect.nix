# Lightweight policy inspection utility.
# Calls resolve functions directly — no full pipeline run.
# Essential for debugging "why did host X get this module?"
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.synthesizePolicies) resolveArgsSatisfied;

  # Schema entity kinds — used to derive targetKey from resolve bindings.
  schemaKinds = den.lib.schemaUtil.schemaEntityKinds;

  # Inspect a policy: call as function, parse typed effects.
  inspectPolicy =
    policy: context: kind:
    let
      rawCall = builtins.tryEval (policy context);
      rawEffects = if rawCall.success then rawCall.value else [ ];
      effects = if builtins.isList rawEffects then rawEffects else [ rawEffects ];
      resolveEffects = builtins.filter (
        e: builtins.isAttrs e && (e.__policyEffect or "") == "resolve" && e.value != { }
      ) effects;
      targets = map (e: e.value) resolveEffects;
      firstResolveEffect = if resolveEffects != [ ] then builtins.head resolveEffects else null;
      effectTargetKind =
        if firstResolveEffect != null then firstResolveEffect.__targetKind or null else null;
      firstKeys = if resolveEffects != [ ] then builtins.attrNames firstResolveEffect.value else [ ];
      # Prefer keys that differ from source kind — those are the new bindings.
      newKeys = builtins.filter (k: k != kind) firstKeys;
      targetKey =
        if effectTargetKind != null then
          effectTargetKind
        else
          lib.findFirst (k: builtins.elem k schemaKinds) (
            if newKeys != [ ] then
              builtins.head newKeys
            else if firstKeys != [ ] then
              builtins.head firstKeys
            else
              kind
          ) (if newKeys != [ ] then newKeys else firstKeys);
    in
    {
      inherit targetKey targets;
      from = kind;
      to = targetKey;
      as = "";
      routing = if kind == targetKey then "sibling" else "child";
    };

  # Unwrap policy registry entries to raw functions.
  unwrapPolicy =
    policy: if builtins.isAttrs policy && policy.__isPolicy or false then policy.fn else policy;

  # Inspect all applicable policies for a given entity kind and context.
  # Returns: { policyName = { targetKey, targets, from, to, as, routing }; }
  #
  # Cheap: only calls resolve functions, no pipeline execution.
  inspect =
    { kind, context }:
    let
      policies = den.policies or { };
      matching = lib.filterAttrs (
        _: policy: resolveArgsSatisfied (unwrapPolicy policy) (context // { __entityKind = kind; })
      ) policies;
    in
    lib.mapAttrs (
      _name: policy: inspectPolicy (unwrapPolicy policy) (context // { __entityKind = kind; }) kind
    ) matching;
in
{
  inherit inspect;
}
