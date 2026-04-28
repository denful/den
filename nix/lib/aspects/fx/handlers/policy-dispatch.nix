# Compile active policies into per-policy named effect handlers.
#
# Each policy becomes a handler for "policy:<name>". The transition
# handler sends these effects to dispatch policies individually,
# enabling granular tracing, per-policy override via scope.provide,
# and routing metadata for provide-to.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.synthesizePolicies)
    ctxSatisfies
    resolveArgsSatisfied
    activePoliciesFor
    ;
  inherit (den.lib.policyTypes)
    isNewStylePolicy
    isOldStylePolicy
    policyFnArgs
    ;

  # Schema entity kinds — used to derive targetKey from resolve binding keys.
  schemaKinds = builtins.filter (
    n: n != "conf" && !(lib.hasPrefix "_" n) && (den.schema.${n}.isEntity or false)
  ) (builtins.attrNames (den.schema or { }));

  # Compile all active policies into named effect handlers.
  # Returns: { "policy:<name>" = handler; ... }
  #
  # Each handler receives pipeline context as param and returns
  # { targets, routing } where routing carries policy metadata
  # for the transition handler's routing decision.
  #
  # Two code paths:
  #   Old-style: attrset with from/to/resolve — existing logic.
  #   New-style: function returning list of typed effects — partition
  #              by __policyEffect tag, derive routing from bindings.
  compilePolicyHandlers =
    let
      policies = den.policies or { };
    in
    lib.mapAttrs' (name: policy: {
      name = "policy:${name}";
      value =
        if isNewStylePolicy policy then newStyleHandler name policy else oldStyleHandler name policy;
    }) policies;

  # Old-style policy handler — unchanged from original implementation.
  oldStyleHandler =
    name: policy:
    { param, state }:
    let
      ctx = param.ctx;
      entityKind = param.entityKind;
      # Merge accumulated traits into resolve context so policies
      # can destructure trait data (entity context wins on collision).
      traits = (state.traits or (_: { })) null;
      resolveCtx = traits // ctx;
      active = activePoliciesFor entityKind ctx;
      isActive = active ? ${name};
      scopeOk = isActive && ctxSatisfies policy.from ctx;
      argsOk = scopeOk && resolveArgsSatisfied policy resolveCtx;
      rawResult = if argsOk then policy.resolve resolveCtx else [ ];
      targets =
        if builtins.isList rawResult then
          rawResult
        else
          builtins.trace "den: policy ${name}: resolve returned non-list, coercing" [ rawResult ];
      targetKey = if policy.as != "" then policy.as else policy.to;
    in
    {
      resume =
        if targets == [ ] then
          null
        else
          {
            inherit targets;
            routing = {
              inherit (policy) from to;
              inherit targetKey;
              policyName = name;
              aspects = policy.aspects or [ ];
              isolateFanOut = policy.isolateFanOut or false;
            };
          };
      inherit state;
    };

  # New-style policy handler — call policy as function, partition typed effects.
  newStyleHandler =
    name: policy:
    { param, state }:
    let
      ctx = param.ctx;
      entityKind = param.entityKind;
      traits = (state.traits or (_: { })) null;
      resolveCtx = traits // ctx;
      # Scope check: if policy carries a `from` field, validate context satisfies it.
      fromKind = if builtins.isAttrs policy then policy.from or null else null;
      scopeOk = fromKind == null || ctxSatisfies fromKind ctx;
      argsOk = scopeOk && resolveArgsSatisfied policy resolveCtx;

      # Call policy function; returns list of typed effects.
      rawEffects = if argsOk then policy resolveCtx else [ ];
      effects =
        if builtins.isList rawEffects then
          rawEffects
        else
          builtins.trace "den: policy ${name}: returned non-list, coercing" [ rawEffects ];

      # Partition effects by __policyEffect tag.
      resolveEffects = builtins.filter (
        e: builtins.isAttrs e && (e.__policyEffect or "") == "resolve" && e.value != { }
      ) effects;
      includeEffects = builtins.filter (
        e: builtins.isAttrs e && (e.__policyEffect or "") == "include"
      ) effects;
      excludeEffects = builtins.filter (
        e: builtins.isAttrs e && (e.__policyEffect or "") == "exclude"
      ) effects;

      # Derive targetKey: explicit `to` on policy attrset wins, then derive from bindings.
      explicitTo = if builtins.isAttrs policy then policy.to or null else null;
      firstResolveKeys =
        if resolveEffects != [ ] then builtins.attrNames (builtins.head resolveEffects).value else [ ];
      targetKey =
        if explicitTo != null then
          explicitTo
        else
          lib.findFirst (k: builtins.elem k schemaKinds) (
            if firstResolveKeys != [ ] then builtins.head firstResolveKeys else entityKind
          ) firstResolveKeys;

      # Extract context attrsets from resolve effects.
      targets = map (e: e.value) resolveEffects;

      # Extract aspect values from include/exclude effects.
      includeAspects = map (e: e.value) includeEffects;
      excludeAspects = map (e: e.value) excludeEffects;

      hasEffects = effects != [ ];
    in
    {
      resume =
        if !hasEffects then
          null
        else
          {
            inherit targets;
            routing = {
              from = entityKind;
              to = targetKey;
              inherit targetKey;
              policyName = name;
              aspects = includeAspects;
              excludes = excludeAspects;
              isolateFanOut =
                if resolveEffects != [ ] && ((builtins.head resolveEffects).__shared or false) then
                  false
                else if builtins.isAttrs policy then
                  policy.isolateFanOut or true
                else
                  true;
            };
          };
      inherit state;
    };

  # Return list of "policy:<name>" effect names for policies matching an entity kind.
  # Old-style: match by policy.from == entityKind.
  # New-style __functor attrsets: use `from` field when present for scoping.
  # New-style plain functions: included unconditionally — resolveArgsSatisfied filters.
  policyEffectNamesFor =
    entityKind:
    let
      policies = den.policies or { };
    in
    lib.concatLists (
      lib.mapAttrsToList (
        name: policy:
        if isNewStylePolicy policy then
          # __functor attrsets can carry a `from` field for entity-kind scoping.
          if builtins.isAttrs policy && policy ? from then
            lib.optional (policy.from == entityKind) "policy:${name}"
          else
            [ "policy:${name}" ]
        else
          lib.optional (policy.from == entityKind) "policy:${name}"
      ) policies
    );
in
{
  inherit compilePolicyHandlers policyEffectNamesFor;
}
