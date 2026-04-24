# Returns null when no policies match (callers decide default).
{
  lib,
  den,
  ...
}:
let
  # Infer the required entity key from a stage name.
  # Derived from den.schema so user-defined entity kinds are supported.
  # from = "host" or "hm-host" implies ctx.host must be an attrset entity.
  # Other stages (flake, flake-system, etc.) have no entity requirement.
  schemaKinds = builtins.filter (n: n != "conf" && !(lib.hasPrefix "_" n)) (
    builtins.attrNames (den.schema or { })
  );
  entityKeyFor =
    stage:
    let
      # Check exact match first, then suffix match (-host → host, -user → user)
      exact = lib.findFirst (k: stage == k) null schemaKinds;
      suffix = lib.findFirst (k: lib.hasSuffix "-${k}" stage) null schemaKinds;
    in
    if exact != null then exact else suffix;

  # Check if context satisfies the scope implied by the stage name.
  #
  # Entity stages (host, *-host, user, *-user, home):
  #   The implied entity key must be present as an attrset.
  #   Policies can safely destructure { host, ... }: etc.
  #
  # Flake stages (flake, flake-*):
  #   No entity values may be present (attrset values in ctx indicate
  #   entity scope). This prevents flake-level policies from firing
  #   during host/user transitions where system is also in context.
  #   No hardcoded entity keys — uses value type detection.
  #
  # Other stages: no restriction.
  ctxSatisfies =
    stage: ctx:
    let
      key = entityKeyFor stage;
      isFlakeScope = stage == "flake" || lib.hasPrefix "flake-" stage;
      hasEntityValues = builtins.any builtins.isAttrs (builtins.attrValues ctx);
    in
    if key != null then
      ctx ? ${key} && builtins.isAttrs ctx.${key}
    else if isFlakeScope then
      !hasEntityValues
    else
      true;

  # Check if policy.resolve's required args are present in ctx.
  # Policies with { system, ... }: won't fire with empty ctx.
  # Policies with _: or { ... }: fire with any ctx.
  resolveArgsSatisfied =
    policy: ctx:
    let
      fargs = lib.functionArgs policy.resolve;
      requiredArgs = builtins.filter (k: !fargs.${k}) (builtins.attrNames fargs);
    in
    builtins.all (k: ctx ? ${k}) requiredArgs;

  # Build the set of active policies for a given stage and context.
  #
  # Activation levels (all additive):
  #   1. Core: policy._core == true → always active
  #   2. Default: policy name in den.default.policies → active globally
  #   3. Schema-kind + entity-instance: entity.policies (merged by module system)
  #      Setting den.schema.host.policies = [...] applies to all hosts.
  #      Setting den.hosts.*.policies = [...] applies to one host.
  #      Both merge via the NixOS module system into entity.policies.
  #
  # Context-aware: when ctx contains entity attrsets, their `.policies`
  # lists are checked for activation.
  #
  # A policy not activated at any level is excluded from the returned set.
  activePoliciesFor =
    stageName: ctx:
    let
      policies = den.policies or { };
      defaultActive = den.default.policies or [ ];
      # Entity activation: read from the entity in context.
      # Schema-kind policies merge into entity.policies via module system.
      entityKind = entityKeyFor stageName;
      entityActive =
        if entityKind != null && ctx ? ${entityKind} && builtins.isAttrs ctx.${entityKind} then
          ctx.${entityKind}.policies or [ ]
        else
          [ ];
      activeNames = defaultActive ++ entityActive;
      activeSet = lib.genAttrs activeNames (_: true);
    in
    lib.filterAttrs (name: policy: policy._core or false || activeSet ? ${name}) policies;

  # NOTE: synthesize does not filter by activation model — all matching
  # policies fire. The pipeline uses per-policy named effects for
  # activation-aware dispatch. synthesize/mergePolicyInto are retained
  # for the policy-inspect utility and potential future direct callers.
  synthesize =
    stageName:
    let
      policies = den.policies or { };
      matching = lib.filter (policy: policy.from == stageName) (builtins.attrValues policies);
    in
    if matching == [ ] then
      null
    else
      rCtx:
      builtins.foldl' (
        acc: policy:
        let
          scopeOk = ctxSatisfies policy.from rCtx;
          argsOk = resolveArgsSatisfied policy rCtx;
          targets = if scopeOk && argsOk then policy.resolve rCtx else [ ];
          targetList =
            if builtins.isList targets then
              targets
            else
              builtins.trace
                "den: policy ${policy.from}->${policy.to}: resolve returned a non-list; coercing to singleton"
                [ targets ];
          key = if policy.as != "" then policy.as else policy.to;
        in
        if targetList == [ ] then acc else acc // { ${key} = (acc.${key} or [ ]) ++ targetList; }
      ) { } matching;

  # Merge an existing into function with synthesized policies for a stage.
  # Existing into takes priority — policies fill in new target keys.
  mergePolicyInto =
    stageName: existingInto:
    let
      policyInto = synthesize stageName;
    in
    if existingInto != null && policyInto != null then
      rCtx:
      let
        existing = existingInto rCtx;
        fromPolicies = policyInto rCtx;
      in
      existing // (builtins.removeAttrs fromPolicies (builtins.attrNames existing))
    else if existingInto != null then
      existingInto
    else
      policyInto;
in
{
  inherit
    synthesize
    mergePolicyInto
    activePoliciesFor
    ctxSatisfies
    resolveArgsSatisfied
    ;
}
