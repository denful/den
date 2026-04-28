# Returns null when no policies match (callers decide default).
{
  lib,
  den,
  ...
}:
let
  # Schema entity kinds (host, user, home, etc.) — used for context checks.
  # Only structural entities (with module content beyond includes) are entity kinds.
  schemaKinds = builtins.filter (
    n: n != "conf" && !(lib.hasPrefix "_" n) && (den.schema.${n}.isEntity or false)
  ) (builtins.attrNames (den.schema or { }));

  # Check if context satisfies the scope implied by the entity kind.
  #
  # Entity kinds (host, user, home):
  #   The kind key must be present as an attrset in context.
  #   Policies can safely destructure { host, ... }: etc.
  #
  # Flake kinds (flake, flake-*):
  #   No entity values may be present (attrset values indicate
  #   entity scope). Prevents flake-level policies from firing
  #   during host/user transitions.
  #
  # Other kinds: no restriction.
  ctxSatisfies =
    kind: ctx:
    let
      isEntityKind = builtins.elem kind schemaKinds;
      isFlakeScope = kind == "flake" || lib.hasPrefix "flake-" kind;
      hasEntityValues = builtins.any builtins.isAttrs (builtins.attrValues ctx);
    in
    if isEntityKind then
      ctx ? ${kind} && builtins.isAttrs ctx.${kind}
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
      inherit (den.lib.policyTypes) isNewStylePolicy policyFnArgs;
      fargs = if isNewStylePolicy policy then policyFnArgs policy else lib.functionArgs policy.resolve;
      requiredArgs = builtins.filter (k: !fargs.${k}) (builtins.attrNames fargs);
      # Trait names are satisfiable — traits get merged into resolve context
      # by policy-dispatch before calling policy.resolve.
      traitNames = den.traits or { };
      requiredArgSatisfied = k: ctx ? ${k} || traitNames ? ${k};
    in
    builtins.all requiredArgSatisfied requiredArgs;

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
    kind: ctx:
    let
      policies = den.policies or { };
      defaultActive = den.default.policies or [ ];
      # Entity activation: read from the entity in context.
      # Schema-kind policies merge into entity.policies via module system.
      isEntityKind = builtins.elem kind schemaKinds;
      entityActive =
        if isEntityKind && ctx ? ${kind} && builtins.isAttrs ctx.${kind} then
          ctx.${kind}.policies or [ ]
        else
          [ ];
      activeNames = defaultActive ++ entityActive;
      activeSet = lib.genAttrs activeNames (_: true);
    in
    lib.filterAttrs (
      name: policy:
      (if builtins.isAttrs policy then policy._core or false else false) || activeSet ? ${name}
    ) policies;

in
{
  inherit
    activePoliciesFor
    ctxSatisfies
    resolveArgsSatisfied
    ;
}
