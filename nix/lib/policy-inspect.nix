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
  schemaKinds = builtins.filter (
    n: n != "conf" && !(lib.hasPrefix "_" n) && (den.schema.${n}.isEntity or false)
  ) (builtins.attrNames (den.schema or { }));

  # Inspect a policy: call as function, parse typed effects.
  inspectPolicy =
    policy: context: kind:
    let
      rawEffects = policy context;
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

  # Inspect all applicable policies for a given entity kind and context.
  # Returns: { policyName = { targetKey, targets, from, to, as, routing }; }
  #
  # Cheap: only calls resolve functions, no pipeline execution.
  inspect =
    { kind, context }:
    let
      globalPolicies = den.policies or { };
      schemaPolicies = (den.schema.${kind} or { }).policies or { };
      policies = globalPolicies // schemaPolicies;
      matching = lib.filterAttrs (
        _: policy: resolveArgsSatisfied policy (context // { __entityKind = kind; })
      ) policies;
    in
    lib.mapAttrs (
      _name: policy: inspectPolicy policy (context // { __entityKind = kind; }) kind
    ) matching;
in
{
  inherit inspect;
}
