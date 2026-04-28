# Policy scope and argument checking utilities.
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

in
{
  inherit
    ctxSatisfies
    resolveArgsSatisfied
    ;
}
