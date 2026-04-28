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
  inherit (den.lib.policyTypes) isNewStylePolicy;

  # Schema entity kinds — used to derive targetKey from new-style resolve bindings.
  schemaKinds = builtins.filter (
    n: n != "conf" && !(lib.hasPrefix "_" n) && (den.schema.${n}.isEntity or false)
  ) (builtins.attrNames (den.schema or { }));

  # Inspect a new-style policy: call as function, parse typed effects.
  inspectNewStyle =
    policy: context: kind:
    let
      rawEffects = policy context;
      effects = if builtins.isList rawEffects then rawEffects else [ rawEffects ];
      resolveEffects = builtins.filter (
        e: builtins.isAttrs e && (e.__policyEffect or "") == "resolve" && e.value != { }
      ) effects;
      targets = map (e: e.value) resolveEffects;
      firstKeys =
        if resolveEffects != [ ] then builtins.attrNames (builtins.head resolveEffects).value else [ ];
      # Prefer keys that differ from source kind — those are the new bindings.
      newKeys = builtins.filter (k: k != kind) firstKeys;
      targetKey = lib.findFirst (k: builtins.elem k schemaKinds) (
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

  # Inspect an old-style policy: access from/to/resolve fields directly.
  inspectOldStyle =
    policy: context:
    let
      targetKey = if policy.as != "" then policy.as else policy.to;
      rawResult = policy.resolve context;
      targets = if builtins.isList rawResult then rawResult else [ rawResult ];
    in
    {
      inherit targetKey targets;
      inherit (policy) from to;
      as = policy.as;
      routing = if policy.from == policy.to then "sibling" else "child";
    };

  # Inspect all applicable policies for a given entity kind and context.
  # Returns: { policyName = { targetKey, targets, from, to, as, routing }; }
  #
  # Cheap: only calls resolve functions, no pipeline execution.
  inspect =
    { kind, context }:
    let
      policies = den.policies or { };
      matching = lib.filterAttrs (
        _: policy: resolveArgsSatisfied policy (context // { __entityKind = kind; })
      ) policies;
    in
    lib.mapAttrs (
      _name: policy:
      if isNewStylePolicy policy then
        inspectNewStyle policy (context // { __entityKind = kind; }) kind
      else
        inspectOldStyle policy context
    ) matching;
in
{
  inherit inspect;
}
